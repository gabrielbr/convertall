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

    func show() {
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
    @State private var dropTargeted = false

    private let missingEncoders = [ImageFormat.webp, .avif].filter { !ImageConverter.canWrite($0) }

    private var brewHint: String {
        let names = missingEncoders.map(\.displayName).joined(separator: " & ")
        let packages = missingEncoders.map { $0 == .webp ? "webp" : "libavif" }.joined(separator: " ")
        return "For \(names) export, run  `brew install \(packages)`"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("ConvertAll")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Convert any image in two clicks.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                Step(number: 1, text: "Right-click an image in Finder.")
                Step(number: 2, text: "Choose **Open With › ConvertAll**\nor **Quick Actions › Convert with ConvertAll**.")
                Step(number: 3, text: "Type or pick a format. The new file appears right next to the original.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            dropZone

            VStack(spacing: 6) {
                Text("Supported images")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(ImageFormat.allCases.map(\.displayName).joined(separator: "  ·  "))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                if !missingEncoders.isEmpty {
                    Text(.init(brewHint))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 16)
        .frame(width: 420)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Drop images here to try it")
                .font(.system(size: 13, weight: .medium))
            Button("Choose Images…", action: choose)
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
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
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
