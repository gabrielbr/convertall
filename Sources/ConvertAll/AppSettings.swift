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

    /// 90s arcade skin. The pop-in picture and sound are the user's own files, copied into
    /// Application Support (never bundled with the app).
    struct Arcade: Codable, Equatable {
        var enabled = false
        /// Big "CONVERTLY!" in the middle of the screen when a conversion finishes.
        var announcer = true
        /// The corner pop-in (with its sound) when several files or a folder finish.
        var popIn = true
        /// ROUND 1 · FIGHT!, hit combos, FLAWLESS VICTORY, K.O., PERFECT!
        var extras = true
        var volume: Double = 0.8
        /// All-time bytes saved by conversions — the HI-SCORE.
        var hiScoreBytes: Int64 = 0

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Arcade()
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            announcer = try c.decodeIfPresent(Bool.self, forKey: .announcer) ?? d.announcer
            popIn = try c.decodeIfPresent(Bool.self, forKey: .popIn) ?? d.popIn
            extras = try c.decodeIfPresent(Bool.self, forKey: .extras) ?? d.extras
            volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
            hiScoreBytes = try c.decodeIfPresent(Int64.self, forKey: .hiScoreBytes) ?? d.hiScoreBytes
        }
    }

    struct Stored: Codable, Equatable {
        var menuBar = false
        var clipboardHotkey = false
        var renameToConvert = false
        var renameFolders: [String] = ["Desktop", "Downloads"].map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path
        }
        var watched: [WatchRule] = []
        var arcade = Arcade()

        init() {}

        /// Every field falls back to its default, so settings saved by older versions survive
        /// when new options are added.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Stored()
            menuBar = try c.decodeIfPresent(Bool.self, forKey: .menuBar) ?? d.menuBar
            clipboardHotkey = try c.decodeIfPresent(Bool.self, forKey: .clipboardHotkey) ?? d.clipboardHotkey
            renameToConvert = try c.decodeIfPresent(Bool.self, forKey: .renameToConvert) ?? d.renameToConvert
            renameFolders = try c.decodeIfPresent([String].self, forKey: .renameFolders) ?? d.renameFolders
            watched = try c.decodeIfPresent([WatchRule].self, forKey: .watched) ?? d.watched
            arcade = try c.decodeIfPresent(Arcade.self, forKey: .arcade) ?? d.arcade
        }
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

    static var bundledCLI: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/convertall") }

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
