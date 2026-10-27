#if os(macOS)
import AppKit
import AVFoundation
import ConvertAllCore
import CoreText
import CryptoKit

/// The 90s fighting-game skin. Listens to conversions and stages the show:
///   • "CONVERTLY!" slammed into the middle of the screen when a conversion finishes
///   • the corner pop-in (with its sound) when several files or a folder finish
///   • ROUND n · FIGHT!, hit combos, FLAWLESS VICTORY, PERFECT!, K.O.
/// The pop-in picture and sound are whatever the user chose in Settings (their own files,
/// kept in Application Support); otherwise an original pixel mascot and a synthesised voice.
final class ArcadeDirector: ObservableObject {
    static let shared = ArcadeDirector()

    enum Style: Equatable { case convertly, round, ko, cheat }

    struct Banner: Equatable, Identifiable {
        let id = UUID()
        let text: String
        var subtitle: String?
        let style: Style
    }

    @Published private(set) var banner: Banner?
    @Published private(set) var combo = 0
    @Published private(set) var showingCombo = false
    @Published private(set) var popInVisible = false

    private var overlay: ArcadeOverlayWindow?
    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private var round = 0
    private var hideBanner: DispatchWorkItem?
    private var hideCombo: DispatchWorkItem?

    private var settings: AppSettings.Arcade { AppSettings.shared.stored.arcade }
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Events from the chip

    func batchStarted(count: Int) {
        combo = 0
        guard settings.enabled, settings.extras, count >= 2 else { return }
        round += 1
        show(Banner(text: "ROUND \(round)", subtitle: "FIGHT!", style: .round), for: 1.3)
        say("Round \(round)... Fight!", pitch: 0.6, rate: 0.45)
    }

    func fileFinished(total: Int) {
        guard settings.enabled, settings.extras, total >= 2 else { return }
        combo += 1
        guard combo >= 2 else { return }
        presentOverlay()
        showingCombo = true
        hideCombo?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showingCombo = false; self?.dismissIfIdle() }
        hideCombo = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    /// - Parameters:
    ///   - inputs: how many files went in (2+ or a folder → the pop-in).
    ///   - saved: bytes saved (adds to the HI-SCORE).
    func finished(outputs: Int, failures: Int, inputs: Int, saved: Int64, ratio: Double?) {
        if saved > 0 { AppSettings.shared.stored.arcade.hiScoreBytes += saved }
        guard settings.enabled else { return }

        if outputs == 0 {
            guard failures > 0, settings.extras else { return }
            show(Banner(text: "K.O.", subtitle: failures > 1 ? "\(failures) FILES DOWN" : nil, style: .ko), for: 1.6)
            say("K. O.", pitch: 0.55, rate: 0.4)
            return
        }

        if settings.announcer {
            var subtitle: String?
            if settings.extras {
                if inputs >= 2, failures == 0 { subtitle = "FLAWLESS VICTORY" }
                if let ratio, ratio >= 0.7 { subtitle = "PERFECT!" }
            }
            show(Banner(text: "CONVERTLY!", subtitle: subtitle, style: .convertly), for: 1.7)
            say(subtitle == "FLAWLESS VICTORY" ? "Convertly! Flawless victory." : "Convertly!", pitch: 0.55, rate: 0.42)
        }
        if settings.popIn, inputs >= 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + (settings.announcer ? 0.9 : 0)) { [weak self] in self?.popIn() }
        }
    }

    /// ↑↑↓↓←→←→BA in the chip.
    func cheatCode(enabled: Bool) {
        show(Banner(text: enabled ? "CHEAT ACTIVATED" : "GAME OVER", subtitle: enabled ? "ARCADE MODE" : nil, style: .cheat), for: 1.6)
        playPopInSound()
    }

    /// Settings' "Test" button: the full batch finale.
    func demo() {
        let wasEnabled = settings.enabled
        if !wasEnabled { AppSettings.shared.stored.arcade.enabled = true }
        finished(outputs: 3, failures: 0, inputs: 3, saved: 0, ratio: nil)
        if !wasEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { AppSettings.shared.stored.arcade.enabled = false }
        }
    }

    // MARK: Staging

    private func show(_ new: Banner, for seconds: TimeInterval) {
        presentOverlay()
        banner = new
        hideBanner?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.banner = nil
            self?.dismissIfIdle()
        }
        hideBanner = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func popIn() {
        presentOverlay()
        playPopInSound()
        popInVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.popInVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.dismissIfIdle() }
        }
    }

    private func presentOverlay() {
        if overlay == nil { overlay = ArcadeOverlayWindow(director: self) }
        overlay?.present()
    }

    private func dismissIfIdle() {
        guard banner == nil, !showingCombo, !popInVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.banner == nil, !self.showingCombo, !self.popInVisible else { return }
            self.overlay?.orderOut(nil)
        }
    }

    // MARK: Sound

    private func say(_ text: String, pitch: Float, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.pitchMultiplier = pitch
        utterance.rate = rate
        utterance.volume = Float(settings.volume)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
    }

    private func playPopInSound() {
        if let url = ArcadeAssets.soundURL, let p = try? AVAudioPlayer(contentsOf: url) {
            p.volume = Float(settings.volume)
            p.play()
            player = p
        } else {
            say("Converty!", pitch: 1.9, rate: 0.55)
        }
    }
}

/// The user's own pop-in picture and sound, copied into Application Support, plus the
/// bundled arcade font (Press Start 2P, SIL Open Font License).
enum ArcadeAssets {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConvertAll/Arcade", isDirectory: true)
    }

    static var imageURL: URL? { find("popin") }
    static var soundURL: URL? { find("sound") }

    static var image: NSImage? { imageURL.flatMap(NSImage.init(contentsOf:)) }

    static func importImage(from url: URL) throws { try store(url, as: "popin") }
    static func importSound(from url: URL) throws { try store(url, as: "sound") }
    static func resetImage() { remove("popin") }
    static func resetSound() { remove("sound") }

    private static func find(_ name: String) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .first { $0.deletingPathExtension().lastPathComponent == name }
    }

    private static func store(_ source: URL, as name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        remove(name)
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name).appendingPathExtension(source.pathExtension))
    }

    private static func remove(_ name: String) {
        while let existing = find(name) { try? FileManager.default.removeItem(at: existing) }
    }

    // MARK: Personal build

    /// A build made on the user's own Mac can embed their arcade picture/sound from the
    /// git-ignored `Support/Personal/` folder (`popin.*`, `sound.*`). On launch they're
    /// installed as the pop-in once per new file, so later choices in Settings — and app
    /// updates, which replace the bundle — don't undo anything.
    static func installPersonalDefaults() {
        guard let personal = Bundle.main.resourceURL?.appendingPathComponent("Personal", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: personal, includingPropertiesForKeys: nil)
        else { return }
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard name == "popin" || name == "sound",
                  let data = try? Data(contentsOf: file) else { continue }
            let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let key = "personalArcade.\(name)"
            guard UserDefaults.standard.string(forKey: key) != fingerprint else { continue }
            if name == "popin" { try? importImage(from: file) } else { try? importSound(from: file) }
            UserDefaults.standard.set(fingerprint, forKey: key)
        }
    }

    static let fontName = "Press Start 2P"

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
#endif
