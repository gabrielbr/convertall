#if os(macOS)
import AppKit
import ConvertAllCore
import QuickLookThumbnailing
import SwiftUI

/// State behind one chip: the file(s) being converted, the format grid, search,
/// keyboard highlight, and the convert → done/failed flow.
final class ChipModel: ObservableObject {
    enum Phase: Equatable {
        case picking
        case converting(ImageFormat, done: Int, total: Int)
        case finished(ImageFormat, outputs: [URL], failures: [String])
        case unsupported(String)
    }

    static let columns = 4

    let files: [URL]
    let formats: [ImageFormat]
    let title: String
    let subtitle: String
    private let available: Set<ImageFormat>

    @Published var query = "" {
        didSet { if let best = matches.first { highlighted = best } }
    }
    @Published var highlighted: ImageFormat?
    @Published private(set) var phase: Phase = .picking
    @Published var thumbnail: NSImage
    /// Corner of the chip nearest the pointer; the appear animation grows from there.
    var anchor: UnitPoint = .topLeading

    var isHovering = false {
        didSet { if !isHovering, autoCloseDeferred { scheduleAutoClose(after: 0.8) } }
    }
    private var autoCloseDeferred = false
    private var autoCloseTask: Task<Void, Never>?

    var onClose: () -> Void = {}

    init(files: [URL]) {
        self.files = files
        let sources = files.map(ImageConverter.sourceFormat(of:))
        let infos = files.map(ImageConverter.info(for:))

        // Same-format output is pointless for a single source format.
        let distinctSources = Set(sources.compactMap { $0 })
        let excluded = distinctSources.count == 1 ? distinctSources.first : nil
        let candidates = ImageFormat.popularityOrder.filter { $0 != excluded }
        let recent = RecentFormats.load().filter(candidates.contains).prefix(3)
        formats = Array(recent) + candidates.filter { !recent.contains($0) }
        available = Set(formats.filter(ImageConverter.canWrite))

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
            title = "\(files.count) images"
            let names = ImageFormat.allCases.filter(distinctSources.contains).map(\.displayName)
            var parts: [String] = []
            if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
            if totalBytes > 0 { parts.append("\(sizeText) total") }
            subtitle = parts.joined(separator: " · ")
        }

        thumbnail = NSWorkspace.shared.icon(forFile: files.first?.path ?? "/")
        highlighted = formats.first(where: available.contains) ?? formats.first

        if sources.allSatisfy({ $0 == nil }) {
            let ext = files.first?.pathExtension.uppercased() ?? ""
            phase = .unsupported(
                "ConvertAll handles images for now\(ext.isEmpty ? "" : " — .\(ext) files aren't supported yet").")
        }
        loadThumbnail()
    }

    // MARK: - Queries for the view

    var matches: [ImageFormat] { FormatSearch.rank(formats, query: query) }
    func isMatch(_ format: ImageFormat) -> Bool { query.isEmpty || matches.contains(format) }
    func isAvailable(_ format: ImageFormat) -> Bool { available.contains(format) }

    var footnote: String {
        guard let f = highlighted else { return "" }
        if !isAvailable(f) { return ImageConverter.installHint(for: f) ?? "Not available on this Mac" }
        return f.blurb
    }

    // MARK: - Actions

    func convertHighlighted(reveal: Bool = false) {
        if let f = highlighted { convert(f, reveal: reveal) }
    }

    func convert(_ format: ImageFormat, reveal: Bool = false) {
        guard phase == .picking else { return }
        guard isAvailable(format) else {
            highlighted = format
            NSSound.beep()
            return
        }
        RecentFormats.record(format)
        phase = .converting(format, done: 0, total: files.count)

        let files = files
        Task { @MainActor in
            var outputs: [URL] = [], failures: [String] = []
            for (i, file) in files.enumerated() {
                do {
                    let out = try await Task.detached(priority: .userInitiated) {
                        try ImageConverter.convert(file, to: format)
                    }.value
                    outputs.append(out)
                } catch {
                    failures.append(files.count == 1
                        ? error.localizedDescription
                        : "\(file.lastPathComponent): \(error.localizedDescription)")
                }
                phase = .converting(format, done: i + 1, total: files.count)
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                phase = .finished(format, outputs: outputs, failures: failures)
            }
            if !outputs.isEmpty {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                if reveal { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
            }
            if failures.isEmpty { scheduleAutoClose(after: reveal ? 0.3 : 2.4) }
        }
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

    /// Arrow keys: spatial in the grid when not searching; through ranked matches when searching.
    func move(dx: Int, dy: Int) {
        guard phase == .picking else { return }
        if !query.isEmpty {
            let list = matches
            guard !list.isEmpty else { return }
            let i = highlighted.flatMap(list.firstIndex(of:)) ?? 0
            highlighted = list[max(0, min(list.count - 1, i + dx + dy))]
            return
        }
        let i = highlighted.flatMap(formats.firstIndex(of:)) ?? 0
        var next = i + dx + dy * Self.columns
        if dy != 0, !formats.indices.contains(next) { next = i }  // don't wrap vertically
        highlighted = formats[max(0, min(formats.count - 1, next))]
    }

    /// Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53:  // esc
            if phase == .picking, !query.isEmpty { query = "" } else { onClose() }
            return true
        case 36, 76:  // return, enter
            switch phase {
            case .picking: convertHighlighted(reveal: cmd)
            case .finished(_, let outputs, _):
                if outputs.isEmpty { backToPicking() } else { revealOutputs() }
            case .unsupported: onClose()
            case .converting: break
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
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { self.thumbnail = image }
        }
    }
}

/// The last few target formats, most recent first — they lead the grid and the
/// very last one is preselected, so repeat conversions are a single ↩.
enum RecentFormats {
    private static let key = "recentTargetFormats"

    static func load() -> [ImageFormat] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(ImageFormat.init(rawValue:))
    }

    static func record(_ format: ImageFormat) {
        let list = [format] + load().filter { $0 != format }
        UserDefaults.standard.set(list.prefix(6).map(\.rawValue), forKey: key)
    }
}
#endif
