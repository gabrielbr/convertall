#if os(macOS)
import AppKit
import ConvertAllCore

/// The always-on features, each opt-in from Settings:
///   • menu bar icon        • ⌥⌘V converts what's on the clipboard
///   • watched folders      • rename-to-convert (rename photo.jpg → photo.png in Finder)
final class BackgroundServices: NSObject {
    static let shared = BackgroundServices()

    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var watchFolders: FolderWatcher?
    private var renameFolders: FolderWatcher?
    /// Paths ConvertAll itself just wrote or moved, so their events are ignored.
    private var ignored: [String: Date] = [:]
    private var pending: [String: DispatchWorkItem] = [:]
    private let workQueue = DispatchQueue(label: "ConvertAll.background", qos: .utility, attributes: .concurrent)
    private let slots = DispatchSemaphore(value: 2)

    private var settings: AppSettings.Stored { AppSettings.shared.stored }

    func apply() {
        applyMenuBar()
        hotKey = settings.clipboardHotkey ? HotKey { [weak self] in self?.convertClipboard() } : nil
        watchFolders = FolderWatcher(paths: settings.watched.map(\.path), latency: 1) { [weak self] in self?.watchedEvents($0) }
        renameFolders = settings.renameToConvert
            ? FolderWatcher(paths: settings.renameFolders, latency: 0.3) { [weak self] in self?.renameEvents($0) }
            : nil
    }

    // MARK: Menu bar

    private func applyMenuBar() {
        guard settings.menuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "ConvertAll")
            statusItem = item
        }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            menu.addItem(item)
        }
        add("Convert Files…", #selector(chooseFiles))
        add("Convert Clipboard", #selector(convertClipboardFromMenu), key: settings.clipboardHotkey ? "v" : "",
            modifiers: [.command, .option])
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), key: ",", modifiers: .command)
        add("Check for Updates…", #selector(checkUpdates))
        menu.addItem(.separator())
        add("Quit ConvertAll", #selector(quit), key: "q", modifiers: .command)
        statusItem?.menu = menu
    }

    @objc private func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Convert"
        guard panel.runModal() == .OK else { return }
        ChipController.shared.present(panel.urls)
    }

    @objc private func convertClipboardFromMenu() { convertClipboard() }
    @objc private func openSettings() { SettingsWindow.shared.show() }
    @objc private func checkUpdates() {
        Task { @MainActor in (NSApp.delegate as? AppDelegate)?.checkForUpdates(nil) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Clipboard

    /// Files on the clipboard open the chip as usual; image data is saved to a scratch
    /// file first. Either way the result goes back onto the clipboard, ready to paste.
    func convertClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            ChipController.shared.present(urls, clipboard: true)
            return
        }
        guard let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            NSSound.beep()
            Notifier.shared.post(title: "Nothing to convert", body: "Copy an image or some files first.", files: [])
            return
        }
        let dir = Self.clipboardFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: ".")
        let url = dir.appendingPathComponent("Clipboard \(stamp).png")
        do {
            try png.write(to: url)
            ChipController.shared.present([url], clipboard: true)
        } catch {
            NSSound.beep()
        }
    }

    static var clipboardFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConvertAll/Clipboard", isDirectory: true)
    }

    /// Clipboard scratch files older than a day are removed at launch.
    static func cleanClipboardFolder() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: clipboardFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(date) > 86_400 { try? fm.removeItem(at: file) }
        }
    }

    // MARK: Shared event plumbing

    private func shouldIgnore(_ path: String) -> Bool {
        let now = Date()
        ignored = ignored.filter { now.timeIntervalSince($0.value) < 30 }
        let name = (path as NSString).lastPathComponent
        let partial = ["crdownload", "download", "part", "partial", "tmp"].contains((name as NSString).pathExtension.lowercased())
        return ignored[path] != nil || name.hasPrefix(".") || partial
    }

    /// Waits until a path has been quiet for `delay`, then runs `body` once.
    private func debounce(_ path: String, delay: TimeInterval, _ body: @escaping () -> Void) {
        pending[path]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pending[path] = nil
            body()
        }
        pending[path] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func runInBackground(_ body: @escaping () -> Void) {
        workQueue.async { [slots] in
            slots.wait()
            defer { slots.signal() }
            body()
        }
    }

    // MARK: Watched folders

    private func watchedEvents(_ events: [FolderWatcher.Event]) {
        for event in events where event.isFile && event.wasCreatedOrChanged && !shouldIgnore(event.path) {
            guard let rule = settings.watched.first(where: { event.path.hasPrefix($0.path + "/") }),
                  !event.path.hasPrefix(rule.path + "/Converted/"),
                  FileFormat(fileExtension: (event.path as NSString).pathExtension) != nil
            else { continue }
            debounce(event.path, delay: 2) { [weak self] in self?.processWatched(event.path, rule: rule) }
        }
    }

    private func processWatched(_ path: String, rule: AppSettings.WatchRule) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path), let source = Converter.sourceFormat(of: url) else { return }
        let target = rule.target ?? source
        guard target == source ? ConversionMatrix.compressible.contains(source)
                               : ConversionMatrix.targets(for: source).contains(target),
              Converter.requirement(from: source, to: target) == .ready
        else { return }
        let options = ConversionOptions(quality: rule.quality)
        let outFolder = rule.url.appendingPathComponent("Converted", isDirectory: true)
        ignored[path] = Date()

        runInBackground { [weak self] in
            do {
                let made = try Converter.convert(url, from: source, to: target, options: options)
                try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)
                var moved: [URL] = []
                for file in made {
                    let dest = OutputNaming.destination(for: file, format: FileFormat(url: file) ?? target, in: outFolder)
                    try FileManager.default.moveItem(at: file, to: dest)
                    moved.append(dest)
                }
                DispatchQueue.main.async {
                    moved.forEach { self?.ignored[$0.path] = Date() }
                    Notifier.shared.post(title: "Converted in “\(rule.url.lastPathComponent)”",
                                         body: url.lastPathComponent + " → " + target.displayName, files: moved)
                }
            } catch {
                DispatchQueue.main.async {
                    Notifier.shared.post(title: "Couldn't convert \(url.lastPathComponent)", body: error.localizedDescription, files: [])
                }
            }
        }
    }

    // MARK: Rename-to-convert

    private func renameEvents(_ events: [FolderWatcher.Event]) {
        for event in events where event.isFile && event.wasRenamed && !shouldIgnore(event.path) {
            guard FileManager.default.fileExists(atPath: event.path) else { continue }  // the "from" half of a rename
            debounce(event.path, delay: 0.6) { [weak self] in self?.processRename(event.path) }
        }
    }

    /// `photo.jpg` renamed to `photo.png` in Finder: still JPEG inside → convert it for real.
    /// The original goes to the Trash, so nothing is lost.
    private func processRename(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard let (actual, wanted) = FileSniffer.renameIntent(for: url),
              Converter.requirement(from: actual, to: wanted) == .ready
        else { return }
        ignored[path] = Date()

        runInBackground { [weak self] in
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("ConvertAll-rename-\(UUID().uuidString)", isDirectory: true)
            let original = work.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(actual.preferredExtension)
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                try fm.moveItem(at: url, to: original)
                do {
                    let made = try Converter.convert(original, from: actual, to: wanted)
                    guard let result = made.first else { throw ConversionError.writeFailed("nothing produced") }
                    try fm.moveItem(at: result, to: url)
                    // Keep the untouched original, renamed back to its real type, in the Trash.
                    try? fm.trashItem(at: original, resultingItemURL: nil)
                    try? fm.removeItem(at: work)
                    DispatchQueue.main.async {
                        self?.ignored[url.path] = Date()
                        Notifier.shared.post(title: "Converted \(url.lastPathComponent)",
                                             body: "\(actual.displayName) → \(wanted.displayName). The original is in the Trash.",
                                             files: [url])
                    }
                } catch {
                    try? fm.moveItem(at: original, to: url)  // put it back as it was
                    throw error
                }
            } catch {
                DispatchQueue.main.async {
                    self?.ignored[url.path] = Date()
                    Notifier.shared.post(title: "Couldn't convert \(url.lastPathComponent)", body: error.localizedDescription, files: [])
                }
            }
        }
    }
}
#endif
