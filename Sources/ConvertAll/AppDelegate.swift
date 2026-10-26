#if os(macOS)
import AppKit
import ConvertAllCore

/// ConvertAll runs as an accessory app: no Dock icon, no menu bar — it appears as a
/// chip next to the pointer when you open an image with it, and quits itself when idle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()
    private var receivedFiles = false
    private var pendingURLs: [URL] = []

    /// How long to stay warm after the chip closes, so back-to-back conversions are instant.
    private let idleTimeout: TimeInterval = 120

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()

        ChipController.shared.onDidClose = { [weak self] in self?.scheduleIdleQuit() }
        WelcomeWindow.shared.onDidClose = { [weak self] in self?.scheduleIdleQuit() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched directly (Launchpad/Finder double-click) rather than via "Open With":
        // explain how to use it instead of showing nothing.
        perform(#selector(showWelcomeIfLaunchedDirectly), with: nil, afterDelay: 0.4)
    }

    @objc private func showWelcomeIfLaunchedDirectly() {
        if !receivedFiles { WelcomeWindow.shared.show() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        open(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindow.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Finder may deliver a multi-selection as several open events; coalesce them into one chip.
    func open(_ urls: [URL]) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(quitIfIdle), object: nil)
        pendingURLs += urls
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(flushPending), object: nil)
        perform(#selector(flushPending), with: nil, afterDelay: 0.08)
    }

    @objc private func flushPending() {
        let urls = pendingURLs
        pendingURLs = []
        guard !urls.isEmpty else { return }
        ChipController.shared.present(urls)
    }

    private func scheduleIdleQuit() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(quitIfIdle), object: nil)
        perform(#selector(quitIfIdle), with: nil, afterDelay: idleTimeout)
    }

    @objc private func quitIfIdle() {
        if !ChipController.shared.isVisible, !WelcomeWindow.shared.isVisible { NSApp.terminate(nil) }
    }
}

/// Invisible for an accessory app, but it's what makes ⌘V/⌘C/⌘A work in the
/// chip's search field and ⌘Q/⌘W work at all.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ConvertAll", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ConvertAll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)

        return main
    }
}
#endif
