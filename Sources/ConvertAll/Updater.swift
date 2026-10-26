#if os(macOS)
import AppKit
import ConvertAllCore

/// Keeps track of whether a newer ConvertAll is on GitHub and installs it on request.
/// Checks quietly at most every few hours; the chip and the welcome window show the result.
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var state: State = .idle

    private let lastCheckKey = "lastUpdateCheck"
    private let interval: TimeInterval = 6 * 3600

    var currentVersion: String { UpdateInstaller.currentVersion.description }

    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > interval { check(userInitiated: false) }
    }

    func check(userInitiated: Bool) {
        guard state != .checking, !isBusy else { return }
        if userInitiated { state = .checking }
        Task { @MainActor in
            do {
                let update = try await UpdateInstaller.fetchLatest()
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                available = update
                state = (update == nil && userInitiated) ? .upToDate : .idle
            } catch {
                state = userInitiated ? .failed("Couldn't check for updates. Are you online?") : .idle
            }
        }
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .installing: true
        default: false
        }
    }

    func install() {
        guard let update = available, !isBusy else { return }
        guard UpdateInstaller.canInstallInPlace else {
            state = .failed("Move ConvertAll to your Applications folder to update it.")
            NSWorkspace.shared.open(update.pageURL)
            return
        }
        state = .downloading(0)
        let box = WeakBox(self)
        Task { @MainActor in
            do {
                try await UpdateInstaller.install(update) { p in
                    DispatchQueue.main.async {
                        guard let self = box.value else { return }
                        self.state = p < 0.9 ? .downloading(p / 0.9) : .installing
                    }
                }
                state = .installing
                UpdateInstaller.relaunch()
                NSApp.terminate(nil)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

/// Lets @Sendable callbacks from background threads reach a main-thread object.
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
#endif
