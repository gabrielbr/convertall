#if os(macOS)
import AppKit
import AVFoundation
import Combine
import ConvertAllCore
import QuickLookThumbnailing
import SwiftUI

/// State behind one chip: the file(s) (folders expanded), the sectioned action grid,
/// search, keyboard highlight, options, trim, and the flow
/// pick → (get engine) → convert in parallel → done/failed.
final class ChipModel: ObservableObject {
    enum Phase: Equatable {
        case picking
        /// The chosen action needs an engine that isn't installed yet.
        case needs(ChipAction, Requirement)
        case installingEngine(ChipAction, progress: Double)
        case trimming
        case converting(ChipAction, progress: Double, done: Int, total: Int)
        case finished(ChipAction, outputs: [URL], failures: [String], skipped: Int)
        case unsupported(String)
        case updating
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let actions: [ChipAction]
    }

    static let columns = 4

    /// Every convertible file in the selection (folders expanded), with its format.
    let files: [URL]
    let sources: [FileFormat]
    private let animated: [Bool]
    private let fileBytes: [Int64]
    let sections: [Section]
    let actions: [ChipAction]
    private let rows: [[ChipAction]]
    let title: String
    let subtitle: String
    private let thumbnailSource: URL?

    @Published var query = "" {
        didSet { if let best = matches.first { highlighted = best } }
    }
    @Published var highlighted: ChipAction?
    @Published private(set) var phase: Phase = .picking
    @Published var thumbnail: NSImage
    @Published private(set) var update: AvailableUpdate?
    @Published private(set) var updateState: Updater.State = .idle
    /// Quality / size / metadata from the options strip; remembered between chips.
    @Published var options = OptionsStore.load() {
        didSet { OptionsStore.save(options) }
    }
    /// Before → after bytes for the finished message.
    @Published private(set) var savings: (before: Int64, after: Int64)?
    /// Length of the (single) audio/video file, once known — enables Trim.
    @Published private(set) var mediaDuration: Double?
    /// Part of the clip to keep. nil = everything.
    @Published var trim: ClosedRange<Double>?

    /// Corner of the chip nearest the pointer; the appear animation grows from there.
    var anchor: UnitPoint = .topLeading

    var isHovering = false {
        didSet { if !isHovering, autoCloseDeferred { scheduleAutoClose(after: 0.8) } }
    }
    private var autoCloseDeferred = false
    private var autoCloseTask: Task<Void, Never>?
    private var runningTasks: [ConversionTask] = []
    private var slotProgress: [Double] = []
    private var completed = 0
    private var subscriptions: Set<AnyCancellable> = []

    var onClose: () -> Void = {}

    init(files selection: [URL]) {
        // Folders become the convertible files inside them; loose files without a known
        // extension are identified by content.
        var found = FolderScanner.expand(selection)
        var formats = found.compactMap(FileFormat.init(url:))
        for url in selection where !found.contains(url) && !FolderScanner.containsFolder([url]) {
            if let f = Converter.sourceFormat(of: url) { found.append(url); formats.append(f) }
        }
        files = found
        sources = formats
        animated = zip(found, formats).map { Converter.isAnimated($0, format: $1) }
        fileBytes = found.map { Int64(ImageConverter.fileSize($0)) }
        thumbnailSource = selection.first

        // Sections: Make smaller · Combine · regular targets (shared by every file, or — for
        // mixed folders — the union, skipping files that can't take the chosen format).
        var sections: [Section] = []
        let distinct = Set(formats)
        if distinct.count == 1, let only = formats.first, ConversionMatrix.compressible.contains(only) {
            sections.append(Section(id: "compress", title: "Make smaller", actions: [.compress(only)]))
        }
        let combine = ConversionMatrix.combineTargets(for: formats)
        if !combine.isEmpty, !(found.count == 1 && formats.first == .pdf) {
            sections.append(Section(id: "combine", title: found.count > 1 ? "Combine" : "Document",
                                    actions: combine.map { .combine($0) }))
        }
        // On-device smart actions for still images.
        if !formats.isEmpty, formats.allSatisfy({ $0.category == .image }) {
            var smart: [ChipAction] = [.extractText]
            if VisionEngine.canRemoveBackground, animated.contains(false) { smart.append(.removeBackground) }
            sections.append(Section(id: "smart", title: "Smart", actions: smart))
        }
        var groups = ConversionMatrix.sections(for: formats)
        if groups.isEmpty, formats.count > 1 {
            var union: [FileFormat] = []
            for f in formats.uniqued() { for t in ConversionMatrix.targets(for: f) where !union.contains(t) { union.append(t) } }
            groups = FormatCategory.allCases.compactMap { cat in
                let fs = union.filter { $0.category == cat }
                return fs.isEmpty ? nil : (category: cat, formats: fs)
            }
        }
        // A single animated image (not GIF, which already has them) can become a video.
        if found.count == 1, animated.first == true, formats.first != .gif {
            groups.append((category: .video, formats: ConversionMatrix.videoOutputs))
        }
        sections += groups.map { Section(id: $0.category.rawValue, title: $0.category.title, actions: $0.formats.map { .convert($0) }) }
        self.sections = sections
        actions = sections.flatMap(\.actions)
        rows = sections.flatMap { section in
            stride(from: 0, to: section.actions.count, by: Self.columns).map {
                Array(section.actions[$0..<min($0 + Self.columns, section.actions.count)])
            }
        }

        // Header.
        let totalBytes = fileBytes.reduce(0, +)
        let sizeText = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let isFolder = selection.count == 1 && FolderScanner.containsFolder(selection)
        if found.count == 1, !isFolder {
            let info = ImageConverter.info(for: found[0])
            title = found[0].lastPathComponent
            var parts: [String] = []
            if let f = info.format { parts.append(f.displayName) }
            if let w = info.pixelWidth, let h = info.pixelHeight { parts.append("\(w)×\(h)") }
            if animated.first == true { parts.append("animated") }
            if totalBytes > 0 { parts.append(sizeText) }
            subtitle = parts.joined(separator: " · ")
        } else {
            let categories = Set(formats.map(\.category))
            let noun = categories.count == 1 ? categories.first!.noun : "files"
            title = isFolder ? selection[0].lastPathComponent : "\(found.count) \(noun)"
            let names = FileFormat.allCases.filter(distinct.contains).map(\.displayName)
            var parts: [String] = isFolder ? ["\(found.count) \(noun)"] : []
            if !names.isEmpty { parts.append(names.count > 4 ? "\(names.prefix(3).joined(separator: ", ")) +\(names.count - 3)" : names.joined(separator: ", ")) }
            if totalBytes > 0 { parts.append(sizeText) }
            subtitle = parts.joined(separator: " · ")
        }

        thumbnail = NSWorkspace.shared.icon(forFile: selection.first?.path ?? "/")
        // Repeat conversions are one ↩: preselect the most recent target that applies here.
        let recent = RecentFormats.load()
        highlighted = recent.lazy.compactMap { f in self.actions.first { $0 == .convert(f) } }.first ?? actions.first

        if actions.isEmpty {
            if found.isEmpty, let first = selection.first {
                let ext = first.pathExtension.uppercased()
                phase = .unsupported(isFolder ? "This folder has no files ConvertAll can convert."
                    : ext.isEmpty ? "ConvertAll doesn't recognise this kind of file." : ".\(ext) files aren't supported yet.")
            } else {
                phase = .unsupported("These files don't share a format they can all become. Try converting them separately.")
            }
        }

        let updater = Updater.shared
        updater.$available.receive(on: RunLoop.main).sink { [weak self] in self?.update = $0 }.store(in: &subscriptions)
        updater.$state.receive(on: RunLoop.main).sink { [weak self] in self?.updateState = $0 }.store(in: &subscriptions)
        loadThumbnail()
        loadDuration()
    }

    // MARK: - Queries for the view

    var fileCount: Int { files.count }
    var matches: [ChipAction] {
        guard !query.isEmpty else { return actions }
        return actions.enumerated()
            .map { ($1, $1.score(query), $0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
    func isMatch(_ action: ChipAction) -> Bool { query.isEmpty || action.score(query) > 0 }

    func label(_ action: ChipAction) -> String { action.label(fileCount: files.count) }
    func blurb(_ action: ChipAction) -> String { action.blurb(fileCount: files.count) }

    private func applies(_ action: ChipAction, to i: Int) -> Bool {
        switch action {
        case .convert(let f): ConversionMatrix.targets(for: sources[i]).contains(f) || (animated[i] && f.category == .video)
        case .compress(let f): sources[i] == f
        case .combine: true
        case .extractText: sources[i].category == .image
        case .removeBackground: sources[i].category == .image && !animated[i]
        }
    }

    /// The strictest requirement across the files the action applies to.
    func requirement(for action: ChipAction) -> Requirement {
        switch action {
        case .combine(let f): return f == .pdf || MediaEngine.ffmpegURL != nil ? .ready : .mediaEngine
        case .extractText, .removeBackground: return .ready
        default: break
        }
        let all = files.indices.filter { applies(action, to: $0) }.map {
            Converter.requirement(from: sources[$0], to: action.format, animated: animated[$0])
        }
        if all.contains(.libreOffice) { return .libreOffice }
        if all.contains(.mediaEngine) { return .mediaEngine }
        return .ready
    }

    var footnote: String {
        guard let a = highlighted else { return "" }
        var text = blurb(a)
        if let trim, canTrim(a) { text = "\(Self.time(trim.lowerBound))–\(Self.time(trim.upperBound)) · " + text }
        switch requirement(for: a) {
        case .ready: return text
        case .mediaEngine: return "\(text) · one-time engine download"
        case .libreOffice: return "\(text) · needs LibreOffice (free)"
        }
    }

    /// Trim applies to a single audio/video file being converted or compressed.
    var canTrim: Bool { files.count == 1 && mediaDuration != nil }
    func canTrim(_ action: ChipAction) -> Bool {
        guard canTrim else { return false }
        switch action {
        case .convert, .compress: return true
        default: return false
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    func resetOptions() { options = ConversionOptions() }

    // MARK: - Actions

    func runHighlighted(reveal: Bool = false) {
        if let a = highlighted { run(a, reveal: reveal) }
    }

    func run(_ action: ChipAction, reveal: Bool = false) {
        guard phase == .picking || phase == .needs(action, .libreOffice) else { return }
        highlighted = action
        switch requirement(for: action) {
        case .ready: start(action, reveal: reveal)
        case let need: withAnimation(.easeOut(duration: 0.15)) { phase = .needs(action, need) }
        }
    }

    func installEngineAndRun() {
        guard case .needs(let action, .mediaEngine) = phase else { return }
        phase = .installingEngine(action, progress: 0)
        let box = WeakBox(self)
        Task { @MainActor in
            do {
                try await MediaPack.install { p in
                    DispatchQueue.main.async { box.value?.phase = .installingEngine(action, progress: p) }
                }
                phase = .picking
                start(action, reveal: false)
            } catch {
                phase = .finished(action, outputs: [], failures: ["Couldn't download the media engine: \(error.localizedDescription)"], skipped: 0)
            }
        }
    }

    func getLibreOffice() {
        NSWorkspace.shared.open(OfficeEngine.downloadPage)
    }

    func beginTrim() {
        guard canTrim, let d = mediaDuration else { return }
        if trim == nil { trim = 0...d }
        withAnimation(.easeOut(duration: 0.15)) { phase = .trimming }
    }

    func endTrim(keep: Bool) {
        if !keep { trim = nil }
        if let t = trim, let d = mediaDuration, t.lowerBound <= 0.05, t.upperBound >= d - 0.05 { trim = nil }
        withAnimation(.easeOut(duration: 0.15)) { phase = .picking }
    }

    private func start(_ action: ChipAction, reveal: Bool) {
        if case .convert(let f) = action { RecentFormats.record(f) }
        savings = nil
        let jobs = files.indices.filter { applies(action, to: $0) }
        let skipped = files.count - jobs.count
        let options = options
        let trim = canTrim(action) ? trim : nil
        let started = Date()
        let box = WeakBox(self)
        let before = jobs.map { fileBytes[$0] }.reduce(0, +)

        if case .combine(let target) = action {
            let files = files, sources = sources
            let task = ConversionTask { p in
                DispatchQueue.main.async { box.value?.report(action, slot: 0, progress: p) }
            }
            begin(action, tasks: [task])
            Task { @MainActor in
                let result = await Self.inBackground { try Combiner.combine(files, sources: sources, to: target, options: options, task: task) }
                switch result {
                case .success(let out): finish(action, outputs: [out], failures: [], skipped: 0, before: before, started: started, reveal: reveal)
                case .failure(let error) where error is CancellationError: backToPicking()
                case .failure(let error): finish(action, outputs: [], failures: [error.localizedDescription], skipped: 0, before: before, started: started, reveal: reveal)
                }
            }
            return
        }

        // Convert / compress: several files at once, as many as the engine handles well.
        let tasks = jobs.indices.map { k in
            ConversionTask { p in DispatchQueue.main.async { box.value?.report(action, slot: k, progress: p) } }
        }
        begin(action, tasks: tasks)
        let first = jobs[0]
        let limit = ConversionMatrix.parallelism(
            for: ConversionMatrix.engine(from: sources[first], to: action.format, animated: animated[first]),
            cores: ProcessInfo.processInfo.activeProcessorCount)
        let files = files, sources = sources
        let target = action.format
        let multiple = jobs.count > 1

        @Sendable func job(_ k: Int) -> @Sendable () async -> (Int, Result<[URL], Error>) {
            let file = files[jobs[k]], source = sources[jobs[k]], task = tasks[k]
            return {
                (k, await ChipModel.inBackground {
                    switch action {
                    case .extractText: [try VisionEngine.extractText(file, from: source, task: task)]
                    case .removeBackground: [try VisionEngine.removeBackground(file, from: source, options: options, task: task)]
                    default: try Converter.convert(file, from: source, to: target, options: options, trim: trim, task: task)
                    }
                })
            }
        }

        Task { @MainActor in
            var outputs: [URL] = [], failures: [String] = []
            var cancelled = false
            await withTaskGroup(of: (Int, Result<[URL], Error>).self) { group in
                var next = 0
                while next < min(limit, jobs.count) {
                    group.addTask(operation: job(next))
                    next += 1
                }
                while let (k, result) = await group.next() {
                    switch result {
                    case .success(let made): outputs += made
                    case .failure(let error) where error is CancellationError: cancelled = true
                    case .failure(let error):
                        let name = files[jobs[k]].lastPathComponent
                        failures.append(multiple ? "\(name): \(error.localizedDescription)" : error.localizedDescription)
                    }
                    completed += 1
                    report(action, slot: k, progress: 1)
                    if !cancelled, next < jobs.count {
                        group.addTask(operation: job(next))
                        next += 1
                    }
                }
            }
            if cancelled, outputs.isEmpty { return backToPicking() }
            finish(action, outputs: outputs, failures: failures, skipped: skipped, before: before, started: started, reveal: reveal)
        }
    }

    private func begin(_ action: ChipAction, tasks: [ConversionTask]) {
        runningTasks = tasks
        slotProgress = Array(repeating: 0, count: tasks.count)
        completed = 0
        phase = .converting(action, progress: 0, done: 0, total: tasks.count)
    }

    private func report(_ action: ChipAction, slot: Int, progress: Double) {
        guard case .converting = phase, slotProgress.indices.contains(slot) else { return }
        slotProgress[slot] = max(slotProgress[slot], progress)
        let overall = slotProgress.reduce(0, +) / Double(max(slotProgress.count, 1))
        phase = .converting(action, progress: overall, done: completed, total: slotProgress.count)
    }

    private func finish(
        _ action: ChipAction, outputs: [URL], failures: [String], skipped: Int,
        before: Int64, started: Date, reveal: Bool
    ) {
        runningTasks = []
        let after = outputs.isEmpty ? 0 : Converter.totalSize(of: outputs)
        if failures.isEmpty, before > 0, after > 0 { savings = (before, after) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            phase = .finished(action, outputs: outputs, failures: failures, skipped: skipped)
        }
        let tookLong = Date().timeIntervalSince(started) > 4
        if !outputs.isEmpty {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            // Long jobs: the user has probably looked away — a soft chime says it's done,
            // and a notification (with "Show in Finder") if they're in another app.
            if tookLong {
                NSSound(named: "Glass")?.play()
                if !NSApp.isActive {
                    let what = outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files"
                    Notifier.shared.post(title: "\(what) ready", body: savingsText ?? blurb(action), files: outputs)
                }
            }
            if reveal { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        }
        if failures.isEmpty { scheduleAutoClose(after: reveal ? 0.3 : (tookLong ? 6 : 2.4)) }
    }

    /// Runs blocking conversion work off the main thread (and off Swift's cooperative pool).
    static func inBackground<T>(_ body: @escaping @Sendable () throws -> T) async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Result { try body() })
            }
        }
    }

    /// "2.4 MB → 680 KB (−72%)" — shown when the result's size is worth mentioning.
    var savingsText: String? {
        guard let s = savings else { return nil }
        let fmt = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let change = Double(s.after - s.before) / Double(s.before) * 100
        guard abs(change) >= 1 else { return "\(fmt(s.after))" }
        return "\(fmt(s.before)) → \(fmt(s.after)) (\(change < 0 ? "−" : "+")\(Int(abs(change).rounded()))%)"
    }

    func cancelConversion() {
        runningTasks.forEach { $0.cancel() }
    }

    func revealOutputs() {
        guard case .finished(_, let outputs, _, _) = phase, !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
        onClose()
    }

    func openOutputs() {
        guard case .finished(_, let outputs, _, _) = phase else { return }
        outputs.prefix(20).forEach { NSWorkspace.shared.open($0) }
        onClose()
    }

    func backToPicking() {
        autoCloseTask?.cancel()
        runningTasks = []
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
        guard phase == .picking, !actions.isEmpty else { return }
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
        else { highlighted = actions.first; return }
        if dy != 0 {
            let nr = max(0, min(rows.count - 1, r + dy))
            highlighted = rows[nr][min(c, rows[nr].count - 1)]
        } else if let i = actions.firstIndex(of: current) {
            highlighted = actions[max(0, min(actions.count - 1, i + dx))]
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
            case .trimming: endTrim(keep: false)
            case .converting: cancelConversion()
            case .installingEngine, .updating: break
            default: onClose()
            }
            return true
        case 36, 76:  // return, enter
            switch phase {
            case .picking: runHighlighted(reveal: cmd)
            case .needs(_, .mediaEngine): installEngineAndRun()
            case .needs(let a, .libreOffice):
                if OfficeEngine.sofficeURL == nil { getLibreOffice() } else { run(a) }
            case .trimming: endTrim(keep: true)
            case .finished(_, let outputs, _, _):
                if outputs.isEmpty { backToPicking() } else { revealOutputs() }
            case .unsupported: onClose()
            default: break
            }
            return true
        case 123, 124, 125, 126, 48:
            guard phase == .picking else { return phase != .trimming }
            switch event.keyCode {
            case 123: move(dx: -1, dy: 0)
            case 124: move(dx: 1, dy: 0)
            case 125: move(dx: 0, dy: 1)
            case 126: move(dx: 0, dy: -1)
            default: move(dx: event.modifierFlags.contains(.shift) ? -1 : 1, dy: 0)
            }
            return true
        default: break
        }
        if cmd, let ch = event.charactersIgnoringModifiers {
            if ch == "w" { onClose(); return true }
            if let n = Int(ch), (1...9).contains(n), actions.indices.contains(n - 1), phase == .picking {
                run(actions[n - 1])
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
        guard let file = thumbnailSource else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 72, height: 72),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let box = WeakBox(self)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { box.value?.thumbnail = image }
        }
    }

    /// Duration of a single audio/video file: AVFoundation first, FFmpeg for the rest (MKV, WebM, …).
    private func loadDuration() {
        guard files.count == 1, [.video, .audio].contains(sources[0].category) else { return }
        let url = files[0]
        let box = WeakBox(self)
        Task { @MainActor in
            var seconds: Double?
            if let d = try? await AVURLAsset(url: url).load(.duration), d.isNumeric, d.seconds > 0 { seconds = d.seconds }
            if seconds == nil, let ffmpeg = MediaEngine.ffmpegURL {
                seconds = try? await Self.inBackground { try MediaEngine.probe(url, ffmpeg: ffmpeg) }.get().duration
            }
            box.value?.mediaDuration = seconds
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// The options strip's settings, remembered across chips.
enum OptionsStore {
    private static let key = "conversionOptions"

    static func load() -> ConversionOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let options = try? JSONDecoder().decode(ConversionOptions.self, from: data)
        else { return ConversionOptions() }
        return options
    }

    static func save(_ options: ConversionOptions) {
        UserDefaults.standard.set(try? JSONEncoder().encode(options), forKey: key)
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
