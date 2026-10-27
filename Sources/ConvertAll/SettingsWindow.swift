#if os(macOS)
import AppKit
import ConvertAllCore
import FinderSync
import SwiftUI
import UniformTypeIdentifiers

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsView())
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "ConvertAll Settings"
            w.isReleasedWhenClosed = false
            w.contentView = hosting
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.windowClosed()
    }
}

private struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show ConvertAll in the menu bar", isOn: $settings.stored.menuBar)
                Toggle("Open at login", isOn: Binding(get: { settings.opensAtLogin }, set: { settings.opensAtLogin = $0 }))
                Toggle("Convert the clipboard with ⌥⌘V", isOn: $settings.stored.clipboardHotkey)
                    .help("Copy an image or files, press ⌥⌘V, pick a format — the result is on the clipboard, ready to paste.")
            } header: {
                Text("General")
            } footer: {
                Text(settings.staysRunning
                     ? "ConvertAll keeps running quietly in the background for these features."
                     : "With everything off, ConvertAll quits itself shortly after each conversion.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("ConvertAll menu in Finder's right-click menu")
                    Spacer()
                    if FIFinderSyncController.isExtensionEnabled {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Turn On…") { FIFinderSyncController.showExtensionManagementInterface() }
                    }
                }
            } header: {
                Text("Finder")
            } footer: {
                Text("Adds one-click presets (Make Smaller, → PNG, → MP4, Combine into One PDF…) right in the menu. Turn on “ConvertAll Finder Menu” under Finder extensions.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Rename to convert", isOn: $settings.stored.renameToConvert)
                if settings.stored.renameToConvert {
                    FolderList(paths: $settings.stored.renameFolders)
                }
            } header: {
                Text("Rename to convert")
            } footer: {
                Text("Rename photo.jpg to photo.png in these folders and ConvertAll really converts it. The original goes to the Trash.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($settings.stored.watched) { $rule in
                    WatchRow(rule: $rule) { settings.stored.watched.removeAll { $0.id == rule.id } }
                }
                Button("Add Folder…") {
                    if let url = chooseFolder() { settings.stored.watched.append(.init(path: url.path)) }
                }
            } header: {
                Text("Watched folders")
            } footer: {
                Text("New files dropped into a watched folder are converted automatically into its “Converted” subfolder.")
                    .foregroundStyle(.secondary)
            }

            ArcadeSection(settings: settings)

            Section {
                HStack {
                    Text("convertall")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    if settings.cliInstalled {
                        Label("Installed in /usr/local/bin", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Install…") { settings.installCLI() }
                    }
                }
                Text("Shortcuts: look for ConvertAll's actions (Convert Files, Make Files Smaller, Combine Files, Extract Text, Remove Background) in the Shortcuts app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Command line & Shortcuts")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 90s fighting-game skin.
private struct ArcadeSection: View {
    @ObservedObject var settings: AppSettings
    @State private var refresh = 0  // re-reads the chosen files after a change

    var body: some View {
        Section {
            Toggle("Arcade mode", isOn: $settings.stored.arcade.enabled)
            if settings.stored.arcade.enabled {
                Toggle("Announcer: “CONVERTLY!” when a conversion finishes", isOn: $settings.stored.arcade.announcer)
                Toggle("Corner pop-in when several files or a folder finish", isOn: $settings.stored.arcade.popIn)
                Toggle("Extras: ROUND · FIGHT!, hit combos, FLAWLESS VICTORY, K.O.", isOn: $settings.stored.arcade.extras)
                HStack {
                    Text("Pop-in picture")
                    Spacer()
                    if let image = ArcadeAssets.image {
                        Image(nsImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fit).frame(height: 28)
                        Button("Reset") { ArcadeAssets.resetImage(); refresh += 1 }
                    } else {
                        Text("Built-in mascot").foregroundStyle(.secondary)
                    }
                    Button("Choose…") { choose(images: true) }
                }
                HStack {
                    Text("Pop-in sound")
                    Spacer()
                    if let sound = ArcadeAssets.soundURL {
                        Text(sound.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                        Button("Reset") { ArcadeAssets.resetSound(); refresh += 1 }
                    } else {
                        Text("Built-in voice").foregroundStyle(.secondary)
                    }
                    Button("Choose…") { choose(images: false) }
                }
                Slider(value: $settings.stored.arcade.volume, in: 0...1) { Text("Volume") }
                HStack {
                    Text("HI-SCORE: \(ByteCountFormatter.string(fromByteCount: settings.stored.arcade.hiScoreBytes, countStyle: .file)) saved")
                        .font(.custom(ArcadeAssets.fontName, size: 10))
                    Spacer()
                    Button("Test") { ArcadeDirector.shared.demo() }
                }
            }
        } header: {
            Text("Arcade")
        } footer: {
            Text("A 90s fighting-game finale for your conversions. Pick your own picture and sound — they stay on this Mac. Secret: ↑↑↓↓←→←→BA in the chip.")
                .foregroundStyle(.secondary)
        }
        .id(refresh)
    }

    private func choose(images: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = images ? [.image] : [.audio]
        panel.prompt = "Use"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if images { try? ArcadeAssets.importImage(from: url) } else { try? ArcadeAssets.importSound(from: url) }
        refresh += 1
    }
}

private struct WatchRow: View {
    @Binding var rule: AppSettings.WatchRule
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder")
            Text(rule.url.lastPathComponent).lineLimit(1).help(rule.path)
            Spacer()
            Picker("", selection: $rule.action) {
                Text("Make smaller").tag("smaller")
                Divider()
                ForEach(FormatCategory.allCases, id: \.self) { category in
                    ForEach(FileFormat.allCases.filter { $0.category == category && $0 != .svg }) { f in
                        Text("→ \(f.displayName)").tag(f.rawValue)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 140)
            Picker("", selection: $rule.quality) {
                ForEach(ConversionOptions.Quality.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            Button(role: .destructive, action: onRemove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }
}

private struct FolderList: View {
    @Binding var paths: [String]

    var body: some View {
        ForEach(paths, id: \.self) { path in
            HStack {
                Image(systemName: "folder")
                Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1)
                Spacer()
                Button { paths.removeAll { $0 == path } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
        }
        Button("Add Folder…") {
            if let url = chooseFolder(), !paths.contains(url.path) { paths.append(url.path) }
        }
    }
}

private func chooseFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url : nil
}
#endif
