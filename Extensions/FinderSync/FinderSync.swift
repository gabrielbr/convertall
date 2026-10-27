import Cocoa
import FinderSync

/// Finder's right-click menu: a "ConvertAll" submenu with one-click presets that fit the
/// selection. The extension is sandboxed, so it only builds the menu and hands the choice
/// to the app through a `convertall://` URL; the app does the converting (and shows
/// progress in its chip).
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Everywhere: the menu should appear for any file the user right-clicks.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard menuKind == .contextualMenuForItems,
              let selection = FIFinderSyncController.default().selectedItemURLs(), !selection.isEmpty
        else { return menu }

        let submenu = NSMenu(title: "ConvertAll")
        add("Convert…", action: "open", to: submenu)
        submenu.addItem(.separator())
        for (title, action) in Presets.items(for: selection) {
            if title == "-" { submenu.addItem(.separator()) } else { add(title, action: action, to: submenu) }
        }

        let root = NSMenuItem(title: "ConvertAll", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    /// Finder rebuilds this menu in its own process and keeps only each item's title, action,
    /// image and tag — not `representedObject` or `target`. So the preset travels as the tag:
    /// its index in `Presets.all`.
    private func add(_ title: String, action: String, to menu: NSMenu) {
        guard let index = Presets.all.firstIndex(of: action) else { return }
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.tag = index
        menu.addItem(item)
    }

    @objc func run(_ sender: NSMenuItem) {
        guard Presets.all.indices.contains(sender.tag),
              let selection = FIFinderSyncController.default().selectedItemURLs(), !selection.isEmpty
        else { return }
        let action = Presets.all[sender.tag]
        var components = URLComponents()
        components.scheme = "convertall"
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "action", value: action)]
            + selection.map { URLQueryItem(name: "path", value: $0.path) }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}

/// The presets offered for a selection, by file kind (extension-based: the sandbox can't
/// read the files themselves).
enum Presets {
    /// Every preset the menu can offer; a menu item's tag is its index here.
    static let all: [String] = ["open", "compress-same", "combine-pdf", "combine-mp4", "extract-text", "remove-background"]
        + ["png", "jpeg", "heic", "webp", "mp4", "gif", "mp3", "m4a", "wav", "docx", "txt", "pdf"].map { "convert-\($0)" }

    static func items(for urls: [URL]) -> [(String, String)] {
        let exts = Set(urls.map { $0.pathExtension.lowercased() })
        let images: Set = ["jpg", "jpeg", "png", "heic", "heif", "webp", "avif", "gif", "tiff", "tif", "bmp", "svg", "ico", "tga", "qoi", "exr", "ppm"]
        let videos: Set = ["mp4", "m4v", "mov", "webm", "mkv", "avi"]
        let audio: Set = ["mp3", "wav", "flac", "aac", "m4a", "ogg", "oga", "opus"]
        let docs: Set = ["docx", "doc", "odt", "rtf", "txt", "html", "htm", "pptx", "ppt", "odp", "xlsx", "xls", "ods", "csv"]
        let isFolder = urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        let only = exts.count == 1 ? exts.first : nil
        var items: [(String, String)] = []

        if isFolder {
            return [("All Images → JPEG", "convert-jpeg"), ("All Images → PNG", "convert-png"), ("All Videos → MP4", "convert-mp4")]
        }
        if exts.isSubset(of: images) {
            if let only, ["jpg", "jpeg", "png", "heic", "webp", "avif", "gif"].contains(only) { items.append(("Make Smaller", "compress-same")) }
            for (title, f) in [("PNG", "png"), ("JPEG", "jpeg"), ("HEIC", "heic"), ("WebP", "webp")] where only.map({ !sameFormat($0, f) }) ?? true {
                items.append(("→ \(title)", "convert-\(f)"))
            }
            items += [("-", ""), (urls.count > 1 ? "Combine into One PDF" : "→ PDF", "combine-pdf"), ("Extract Text", "extract-text"),
                      ("Remove Background", "remove-background")]
        } else if exts.isSubset(of: videos) {
            items.append(("Make Smaller", "compress-same"))
            for (title, f) in [("MP4", "mp4"), ("GIF", "gif"), ("MP3 (audio)", "mp3")] where only.map({ !sameFormat($0, f) }) ?? true {
                items.append(("→ \(title)", "convert-\(f)"))
            }
            if urls.count > 1 { items.append(("Join into One MP4", "combine-mp4")) }
        } else if exts.isSubset(of: audio) {
            if let only, only != "wav", only != "flac" { items.append(("Make Smaller", "compress-same")) }
            for (title, f) in [("MP3", "mp3"), ("M4A", "m4a"), ("WAV", "wav")] where only.map({ !sameFormat($0, f) }) ?? true {
                items.append(("→ \(title)", "convert-\(f)"))
            }
        } else if exts == ["pdf"] {
            items += [("Make Smaller", "compress-same"), ("→ Word (DOCX)", "convert-docx"), ("→ PNG (pages)", "convert-png"), ("→ Text", "convert-txt")]
            if urls.count > 1 { items.append(("Combine into One PDF", "combine-pdf")) }
        } else if exts.isSubset(of: docs) {
            items += [("→ PDF", "convert-pdf"), ("→ PNG (pages)", "convert-png")]
        }
        return items
    }

    private static func sameFormat(_ ext: String, _ format: String) -> Bool {
        ext == format || (ext == "jpg" && format == "jpeg") || (ext == "m4v" && format == "mp4") || (ext == "heif" && format == "heic")
    }
}
