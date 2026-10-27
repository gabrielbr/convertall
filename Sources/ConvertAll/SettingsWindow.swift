#if os(macOS)
import AppKit
import ConvertAllCore
import SwiftUI

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
