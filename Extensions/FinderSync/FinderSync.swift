import Cocoa
import ConvertAllCore
import FinderSync

/// Finder's right-click menu: a "ConvertAll ▸" submenu with one-click presets that fit the
/// selection (chosen in ConvertAll's Settings). The extension is sandboxed, so it only builds
/// the menu and hands the choice to the app through a `convertall://` URL; the app does the
/// converting and shows progress in its chip.
final class FinderSync: FIFinderSync {
    private static let cacheKey = "presets"

    /// The user's choice, as last sent by the app (kept, so the menu is right even when
    /// ConvertAll isn't running).
    private var config: FinderPresets.Config? =
        UserDefaults.standard.string(forKey: FinderSync.cacheKey).flatMap(FinderPresets.decode)

    override init() {
        super.init()
        // Everywhere: the menu should appear for any file the user right-clicks.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(presetsChanged(_:)),
                           name: Notification.Name(FinderPresets.notificationName), object: nil,
                           suspensionBehavior: .deliverImmediately)
        // Ask a running ConvertAll for the current presets.
        center.postNotificationName(Notification.Name(FinderPresets.requestNotificationName), object: nil,
                                    userInfo: nil, deliverImmediately: true)
    }

    @objc private func presetsChanged(_ note: Notification) {
        guard let json = note.object as? String, let decoded = FinderPresets.decode(json) else { return }
        config = decoded
        UserDefaults.standard.set(json, forKey: Self.cacheKey)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard menuKind == .contextualMenuForItems,
              let selection = FIFinderSyncController.default().selectedItemURLs(), !selection.isEmpty
        else { return menu }

        let isFolder = selection.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        let submenu = NSMenu(title: "ConvertAll")
        add("Convert…", id: "open", to: submenu)
        let presets = FinderPresets.items(for: selection, isFolder: isFolder, config: config)
        if !presets.isEmpty { submenu.addItem(.separator()) }
        for preset in presets { add(preset.title, id: preset.id, to: submenu) }

        let root = NSMenuItem(title: "ConvertAll", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    /// Finder rebuilds this menu in its own process and keeps only each item's title, action,
    /// image and tag — so the preset travels as the tag: its index in `FinderPresets.all`.
    private func add(_ title: String, id: String, to menu: NSMenu) {
        guard let index = FinderPresets.all.firstIndex(of: id) else { return }
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.tag = index
        menu.addItem(item)
    }

    @objc func run(_ sender: NSMenuItem) {
        guard FinderPresets.all.indices.contains(sender.tag),
              let selection = FIFinderSyncController.default().selectedItemURLs(), !selection.isEmpty
        else { return }
        var components = URLComponents()
        components.scheme = "convertall"
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "action", value: FinderPresets.all[sender.tag])]
            + selection.map { URLQueryItem(name: "path", value: $0.path) }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
