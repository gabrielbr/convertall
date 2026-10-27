#if os(macOS)
import AppKit
import ConvertAllCore
import SwiftUI
import UniformTypeIdentifiers

/// Shown only when ConvertAll is launched directly: teaches the right-click flow
/// and doubles as a drop target for trying it out.
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private var window: NSWindow?
    var onDidClose: () -> Void = {}
    var isVisible: Bool { window?.isVisible ?? false }
    private var autoShownAt: Date?

    /// Closes the window if it appeared by itself at launch moments ago (not if the user opened it).
    func closeIfJustShownAutomatically() {
        guard let shown = autoShownAt, Date().timeIntervalSince(shown) < 5, isVisible else { return }
        autoShownAt = nil
        window?.orderOut(nil)
    }

    func show(automatically: Bool = false) {
        autoShownAt = automatically ? Date() : nil
        if window == nil {
            let hosting = NSHostingView(rootView: WelcomeView())
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = hosting
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onDidClose() }
}

private struct WelcomeView: View {
    @ObservedObject private var updater = Updater.shared
    @StateObject private var extras = ExtrasModel()
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("ConvertAll")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Images, video, audio and documents — converted in two clicks.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                Step(number: 1, text: "Right-click a file in Finder.")
                Step(number: 2, text: "Choose **Open With › ConvertAll**\nor **Quick Actions › Convert with ConvertAll**.")
                Step(number: 3, text: "Type or pick a format. The new file appears right next to the original.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            dropZone

            extrasBox

            HStack(spacing: 8) {
                Text("Version \(updater.currentVersion)")
                    .foregroundStyle(.tertiary)
                Button("Settings…") { SettingsWindow.shared.show() }
                    .buttonStyle(.link)
                Spacer()
                updateStatus
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .padding(.top, 16)
        .frame(width: 440)
        .onAppear { extras.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extras.refresh()  // picks up a fresh LibreOffice install
        }
    }

    // MARK: Extras

    private var extrasBox: some View {
        VStack(spacing: 0) {
            ExtraRow(
                symbol: "film", title: "Media engine",
                detail: "Video, audio, GIF ↔ video, WebP & AVIF export",
                installed: extras.mediaInstalled
            ) {
                if let p = extras.mediaProgress {
                    ProgressView(value: p).frame(width: 90)
                } else {
                    Button("Download · \(MediaPack.downloadSizeText)") { extras.installMedia() }
                        .controlSize(.small)
                }
            }
            Divider().padding(.leading, 40)
            ExtraRow(
                symbol: "tablecells", title: "LibreOffice",
                detail: "Spreadsheets & presentations (free)",
                installed: extras.officeInstalled
            ) {
                Button("Get LibreOffice") { NSWorkspace.shared.open(OfficeEngine.downloadPage) }
                    .controlSize(.small)
            }
            if let error = extras.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.state {
        case .checking:
            ProgressView().controlSize(.mini)
            Text("Checking…").foregroundStyle(.secondary)
        case .downloading(let p):
            ProgressView(value: p).frame(width: 80)
            Text("Downloading update…").foregroundStyle(.secondary)
        case .installing:
            Text("Installing… ConvertAll will reopen").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).lineLimit(1)
            Button("Retry") { updater.check(userInitiated: true) }.controlSize(.small)
        default:
            if let update = updater.available {
                Text("Version \(update.version.description) is available").foregroundStyle(.secondary)
                Button("Update") { updater.install() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            } else {
                if updater.state == .upToDate {
                    Label("Up to date", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Check for Updates") { updater.check(userInitiated: true) }
                    .controlSize(.small)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Drop files here to try it")
                .font(.system(size: 13, weight: .medium))
            Button("Choose Files…", action: choose)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.primary.opacity(0.15))
        )
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers)
            return true
        }
    }

    private func loadURLs(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let collected = URLCollector()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collected.urls
            Task { @MainActor in (NSApp.delegate as? AppDelegate)?.open(urls) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = FileFormat.allCases.flatMap(\.typeIdentifiers).compactMap { UTType($0) } + [.folder]
        panel.prompt = "Convert"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { @MainActor in (NSApp.delegate as? AppDelegate)?.open(urls) }
    }
}

/// Thread-safe accumulator for drop callbacks, which arrive on background queues.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
}

/// Install state of the optional engines, for the welcome window.
private final class ExtrasModel: ObservableObject {
    @Published var mediaInstalled = false
    @Published var officeInstalled = false
    @Published var mediaProgress: Double?
    @Published var error: String?

    func refresh() {
        mediaInstalled = MediaEngine.ffmpegURL != nil
        officeInstalled = OfficeEngine.sofficeURL != nil
    }

    func installMedia() {
        mediaProgress = 0
        error = nil
        let box = WeakBox(self)
        Task { @MainActor in
            do {
                try await MediaPack.install { p in DispatchQueue.main.async { box.value?.mediaProgress = p } }
            } catch {
                self.error = "Download failed: \(error.localizedDescription)"
            }
            mediaProgress = nil
            refresh()
        }
    }
}

private struct ExtraRow<Action: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let installed: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                action()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
