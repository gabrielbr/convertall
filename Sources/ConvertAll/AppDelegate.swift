#if os(macOS)
import AppKit
import ConvertAllCore

/// ConvertAll runs as an accessory app: no Dock icon — it appears as a chip next to the
/// pointer when you open a file with it, and quits itself when idle unless a background
/// feature (menu bar, clipboard hotkey, watched folders, rename-to-convert) is on.
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
        Notifier.shared.setUp()
        NSUpdateDynamicServices()

        ChipController.shared.onDidClose = { [weak self] in self?.scheduleIdleQuit() }
        WelcomeWindow.shared.onDidClose = { [weak self] in self?.scheduleIdleQuit() }
        AppSettings.shared.onChange = { [weak self] in
            BackgroundServices.shared.apply()
            self?.scheduleIdleQuit()
        }
        BackgroundServices.shared.apply()
        BackgroundServices.cleanClipboardFolder()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.checkIfDue()
        // macOS tells us whether this is a plain launch (Launchpad, double-clicking the app)
        // or one to open files / handle a link (Open With, Quick Action, Finder menu). Only a
        // plain launch gets the welcome window — never guess from timing, because files can
        // arrive well after launch on a cold start.
        let plainLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        guard plainLaunch else { return scheduleIdleQuit() }
        perform(#selector(showWelcomeIfLaunchedDirectly), with: nil, afterDelay: 0.4)
    }

    @objc private func showWelcomeIfLaunchedDirectly() {
        // Not when opening files, when a Shortcut launched us, or when the menu bar icon is there
        // (e.g. opened at login).
        guard !receivedFiles, !IntentActivity.started, !AppSettings.shared.stored.menuBar else {
            return scheduleIdleQuit()
        }
        WelcomeWindow.shared.show(automatically: true)
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindow.shared.show()
    }

    func windowClosed() { scheduleIdleQuit() }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showWelcomeIfLaunchedDirectly), object: nil)
        // Files beat the welcome window: if it just popped up on its own, take it away again.
        WelcomeWindow.shared.closeIfJustShownAutomatically()
        for url in urls where url.scheme == "convertall" { handle(url) }
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { open(files) }
    }

    /// `convertall://run?action=convert-png&path=/a.jpg&path=/b.jpg` from the Finder menu.
    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let paths = items.filter { $0.name == "path" }.compactMap(\.value).map { URL(fileURLWithPath: $0) }
        guard !paths.isEmpty else { return }
        let action = items.first { $0.name == "action" }?.value
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(quitIfIdle), object: nil)
        ChipController.shared.present(paths, run: action == "open" ? nil : action)
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

    @objc func checkForUpdates(_ sender: Any?) {
        WelcomeWindow.shared.show()
        Updater.shared.check(userInitiated: true)
    }

    @objc private func quitIfIdle() {
        guard !Updater.shared.isBusy else { return scheduleIdleQuit() }
        guard !AppSettings.shared.staysRunning else { return }
        if !ChipController.shared.isVisible, !WelcomeWindow.shared.isVisible, !SettingsWindow.shared.isVisible {
            NSApp.terminate(nil)
        }
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
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
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
