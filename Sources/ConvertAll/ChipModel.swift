#if os(macOS)
import AppKit
import Combine
import ConvertAllCore
import QuickLookThumbnailing
import SwiftUI

/// State behind one chip: the file(s), the sectioned format grid, search, keyboard
/// highlight, and the flow pick → (get engine) → convert → done/failed.
final class ChipModel: ObservableObject {
    enum Phase: Equatable {
        case picking
        /// The chosen format needs an engine that isn't installed yet.
        case needs(FileFormat, Requirement)
        case installingEngine(FileFormat, progress: Double)
        case converting(FileFormat, progress: Double, done: Int, total: Int)
        case finished(FileFormat, outputs: [URL], failures: [String])
        case unsupported(String)
        case updating
    }

    struct Section: Identifiable {
        let category: FormatCategory
        let formats: [FileFormat]
        var id: FormatCategory { category }
    }

    static let columns = 4

    let files: [URL]
    let sources: [FileFormat]
    let sections: [Section]
    let formats: [FileFormat]
    private let rows: [[FileFormat]]
    let title: String
    let subtitle: String

    @Published var query = "" {
        didSet { if let best = matches.first { highlighted = best } }
    }
    @Published var highlighted: FileFormat?
    @Published private(set) var phase: Phase = .picking
    @Published var thumbnail: NSImage
    @Published private(set) var update: AvailableUpdate?
    @Published private(set) var updateState: Updater.State = .idle

    /// Corner of the chip nearest the pointer; the appear animation grows from there.
    var anchor: UnitPoint = .topLeading

    var isHovering = false {
        didSet { if !isHovering, autoCloseDeferred { scheduleAutoClose(after: 0.8) } }
    }
    private var autoCloseDeferred = false
    private var autoCloseTask: Task<Void, Never>?
    private var currentTask: ConversionTask?
    private var subscriptions: Set<AnyCancellable> = []

    var onClose: () -> Void = {}

    init(files: [URL]) {
        self.files = files
        let detected = files.map(Converter.sourceFormat(of:))
        sources = detected.compactMap { $0 }
        let infos = files.map(ImageConverter.info(for:))

        sections = detected.contains(nil) ? [] : ConversionMatrix.sections(for: sources).map {
            Section(category: $0.category, formats: $0.formats)
        }
        formats = sections.flatMap(\.formats)
        rows = sections.flatMap { section in
            stride(from: 0, to: section.formats.count, by: Self.columns).map {
                Array(section.formats[$0..<min($0 + Self.columns, section.formats.count)])
            }
        }

        let totalBytes = infos.compactMap(\.byteCount).reduce(0, +)
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        if files.count == 1, let info = infos.first {
            title = files[0].lastPathComponent
            var parts: [String] = []
            if let f = info.format { parts.append(f.displayName) }
            if let w = info.pixelWidth, let h = info.pixelHeight { parts.append("\(w)×\(h)") }
            if totalBytes > 0 { parts.append(sizeText) }
            subtitle = parts.joined(separator: " · ")
        } else {
            let categories = Set(sources.map(\.category))
            title = "\(files.count) \(categories.count == 1 ? categories.first!.noun : "files")"
            let names = FileFormat.allCases.filter(Set(sources).contains).map(\.displayName)
            var parts: [String] = []
            if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
            if totalBytes > 0 { parts.append("\(sizeText) total") }
            subtitle = parts.joined(separator: " · ")
        }

        thumbnail = NSWorkspace.shared.icon(forFile: files.first?.path ?? "/")
        // Repeat conversions are one ↩: preselect the most recent target that applies here.
        highlighted = RecentFormats.load().first(where: formats.contains) ?? formats.first

        if formats.isEmpty {
            if let unknown = files.first(where: { Converter.sourceFormat(of: $0) == nil }) {
                let ext = unknown.pathExtension.uppercased()
                phase = .unsupported(ext.isEmpty
                    ? "ConvertAll doesn't recognise this kind of file."
                    : ".\(ext) files aren't supported yet.")
            } else {
                phase = .unsupported("These files don't share a format they can all become. Try converting them separately.")
            }
        }

        let updater = Updater.shared
        updater.$available.receive(on: RunLoop.main).sink { [weak self] in self?.update = $0 }.store(in: &subscriptions)
        updater.$state.receive(on: RunLoop.main).sink { [weak self] in self?.updateState = $0 }.store(in: &subscriptions)
        loadThumbnail()
    }

    // MARK: - Queries for the view

    var matches: [FileFormat] { FormatSearch.rank(formats, query: query) }
    func isMatch(_ format: FileFormat) -> Bool { query.isEmpty || matches.contains(format) }

    /// The strictest requirement across every selected file.
    func requirement(for target: FileFormat) -> Requirement {
        let all = sources.map { Converter.requirement(from: $0, to: target) }
        if all.contains(.libreOffice) { return .libreOffice }
        if all.contains(.mediaEngine) { return .mediaEngine }
        return .ready
    }

    var footnote: String {
        guard let f = highlighted else { return "" }
        switch requirement(for: f) {
        case .ready: return f.blurb
        case .mediaEngine: return "\(f.blurb) · one-time engine download"
        case .libreOffice: return "\(f.blurb) · needs LibreOffice (free)"
        }
    }

    // MARK: - Actions

    func convertHighlighted(reveal: Bool = false) {
        if let f = highlighted { convert(f, reveal: reveal) }
    }

    func convert(_ format: FileFormat, reveal: Bool = false) {
        guard phase == .picking || phase == .needs(format, .libreOffice) else { return }
        highlighted = format
        switch requirement(for: format) {
        case .ready: start(format, reveal: reveal)
        case let need: withAnimation(.easeOut(duration: 0.15)) { phase = .needs(format, need) }
        }
    }

    func installEngineAndConvert() {
        guard case .needs(let format, .mediaEngine) = phase else { return }
        phase = .installingEngine(format, progress: 0)
        let box = WeakBox(self)
        Task { @MainActor in
            do {
                try await MediaPack.install { p in
                    DispatchQueue.main.async { box.value?.phase = .installingEngine(format, progress: p) }
                }
                phase = .picking
                start(format, reveal: false)
            } catch {
                phase = .finished(format, outputs: [], failures: ["Couldn't download the media engine: \(error.localizedDescription)"])
            }
        }
    }

    func getLibreOffice() {
        NSWorkspace.shared.open(OfficeEngine.downloadPage)
    }

    private func start(_ format: FileFormat, reveal: Bool) {
        RecentFormats.record(format)
        phase = .converting(format, progress: 0, done: 0, total: files.count)
        let started = Date()
        let jobs = Array(zip(files, sources))
        let box = WeakBox(self)

        Task { @MainActor in
            var outputs: [URL] = [], failures: [String] = []
            var cancelled = false
            for (i, (file, source)) in jobs.enumerated() {
                let total = jobs.count
                let task = ConversionTask { p in
                    DispatchQueue.main.async {
                        guard let model = box.value, case .converting = model.phase else { return }
                        model.phase = .converting(format, progress: (Double(i) + p) / Double(total), done: i, total: total)
                    }
                }
                currentTask = task
                do {
                    let made = try await Task.detached(priority: .userInitiated) {
                        try Converter.convert(file, from: source, to: format, task: task)
                    }.value
                    outputs += made
                } catch is CancellationError {
                    cancelled = true
                    break
                } catch {
                    failures.append(jobs.count == 1
                        ? error.localizedDescription
                        : "\(file.lastPathComponent): \(error.localizedDescription)")
                }
                phase = .converting(format, progress: Double(i + 1) / Double(total), done: i + 1, total: total)
            }
            currentTask = nil

            if cancelled {
                withAnimation(.easeOut(duration: 0.15)) { phase = outputs.isEmpty ? .picking : .finished(format, outputs: outputs, failures: []) }
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                phase = .finished(format, outputs: outputs, failures: failures)
            }
            let tookLong = Date().timeIntervalSince(started) > 4
            if !outputs.isEmpty {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                // Long jobs: the user has probably looked away — a soft chime says it's done.
                if tookLong { NSSound(named: "Glass")?.play() }
                if reveal { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
            }
            if failures.isEmpty { scheduleAutoClose(after: reveal ? 0.3 : (tookLong ? 6 : 2.4)) }
        }
    }

    func cancelConversion() {
        currentTask?.cancel()
    }

    func revealOutputs() {
        guard case .finished(_, let outputs, _) = phase, !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
        onClose()
    }

    func openOutputs() {
        guard case .finished(_, let outputs, _) = phase else { return }
        outputs.forEach { NSWorkspace.shared.open($0) }
        onClose()
    }

    func backToPicking() {
        autoCloseTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { phase = .picking }
    }

    func installUpdate() {
        guard update != nil else { return }
        autoCloseTask?.cancel()
        phase = .updating
        Updater.shared.install()
    }

    /// Arrow keys: spatial in the grid when not searching; through ranked matches when searching.
    func move(dx: Int, dy: Int) {
        guard phase == .picking, !formats.isEmpty else { return }
        if !query.isEmpty {
            let list = matches
            guard !list.isEmpty else { return }
            let i = highlighted.flatMap(list.firstIndex(of:)) ?? 0
            highlighted = list[max(0, min(list.count - 1, i + dx + dy))]
            return
        }
        guard let current = highlighted,
              let r = rows.firstIndex(where: { $0.contains(current) }),
              let c = rows[r].firstIndex(of: current)
        else { highlighted = formats.first; return }
        if dy != 0 {
            let nr = max(0, min(rows.count - 1, r + dy))
            highlighted = rows[nr][min(c, rows[nr].count - 1)]
        } else if let i = formats.firstIndex(of: current) {
            highlighted = formats[max(0, min(formats.count - 1, i + dx))]
        }
    }

    /// Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53:  // esc
            switch phase {
            case .picking where !query.isEmpty: query = ""
            case .needs: backToPicking()
            case .converting: cancelConversion()
            case .installingEngine, .updating: break
            default: onClose()
            }
            return true
        case 36, 76:  // return, enter
            switch phase {
            case .picking: convertHighlighted(reveal: cmd)
            case .needs(_, .mediaEngine): installEngineAndConvert()
            case .needs(let f, .libreOffice):
                if OfficeEngine.sofficeURL == nil { getLibreOffice() } else { convert(f) }
            case .finished(_, let outputs, _):
                if outputs.isEmpty { backToPicking() } else { revealOutputs() }
            case .unsupported: onClose()
            default: break
            }
            return true
        case 123: move(dx: -1, dy: 0); return true
        case 124: move(dx: 1, dy: 0); return true
        case 125: move(dx: 0, dy: 1); return true
        case 126: move(dx: 0, dy: -1); return true
        case 48: move(dx: event.modifierFlags.contains(.shift) ? -1 : 1, dy: 0); return true
        default: break
        }
        if cmd, let ch = event.charactersIgnoringModifiers {
            if ch == "w" { onClose(); return true }
            if let n = Int(ch), (1...9).contains(n), formats.indices.contains(n - 1), phase == .picking {
                convert(formats[n - 1])
                return true
            }
        }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .converting, .installingEngine, .updating: true
        default: false
        }
    }

    // MARK: - Private

    private func scheduleAutoClose(after delay: TimeInterval) {
        autoCloseTask?.cancel()
        autoCloseDeferred = false
        autoCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.isHovering { self.autoCloseDeferred = true } else { self.onClose() }
        }
    }

    private func loadThumbnail() {
        guard let file = files.first else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 72, height: 72),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let box = WeakBox(self)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { box.value?.thumbnail = image }
        }
    }
}

/// The last few target formats, most recent first. The most recent one that fits
/// the current file is preselected, so repeat conversions are a single ↩.
enum RecentFormats {
    private static let key = "recentTargetFormats"

    static func load() -> [FileFormat] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(FileFormat.init(rawValue:))
    }

    static func record(_ format: FileFormat) {
        let list = [format] + load().filter { $0 != format }
        UserDefaults.standard.set(list.prefix(12).map(\.rawValue), forKey: key)
    }
}
#endif
