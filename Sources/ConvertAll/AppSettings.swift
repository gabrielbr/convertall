#if os(macOS)
import AppKit
import ConvertAllCore
import ServiceManagement

/// Everything the Settings window controls, persisted in UserDefaults. Changing any of it
/// re-applies the background services (menu bar, hotkey, folder watchers).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    struct WatchRule: Codable, Identifiable, Equatable {
        var id = UUID()
        var path: String
        /// A format's raw value, or "smaller" for Make smaller.
        var action: String = "smaller"
        var quality: ConversionOptions.Quality = .balanced

        var url: URL { URL(fileURLWithPath: path) }
        var target: FileFormat? { FileFormat(rawValue: action) }
    }

    struct Stored: Codable, Equatable {
        var menuBar = false
        var clipboardHotkey = false
        var renameToConvert = false
        var renameFolders: [String] = ["Desktop", "Downloads"].map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path
        }
        var watched: [WatchRule] = []
    }

    @Published var stored: Stored {
        didSet {
            guard stored != oldValue else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: Self.key)
            onChange?()
        }
    }

    /// Set by the app delegate: re-applies background services.
    var onChange: (() -> Void)?

    private static let key = "appSettings"

    private init() {
        stored = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    /// Any feature that has to keep ConvertAll running in the background.
    var staysRunning: Bool {
        stored.menuBar || stored.clipboardHotkey || stored.renameToConvert || !stored.watched.isEmpty
    }

    // MARK: Open at login (macOS 13 ServiceManagement)

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSSound.beep()
            }
        }
    }

    // MARK: Command-line tool

    static let cliLink = URL(fileURLWithPath: "/usr/local/bin/convertall")

    static var bundledCLI: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/convertall") }

    var cliInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: Self.cliLink.path)) == Self.bundledCLI.path
    }

    /// Links /usr/local/bin/convertall to the copy inside the app (asks for an admin password).
    func installCLI() {
        let target = Self.bundledCLI.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "do shell script \"mkdir -p /usr/local/bin && ln -sf '\(target)' /usr/local/bin/convertall\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        objectWillChange.send()
    }
}
#endif
