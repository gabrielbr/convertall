#if os(macOS)
import AppKit
import ConvertAllCore
import SwiftUI

/// The floating chip. One fixed footprint for every phase (pick → converting → done),
/// so it never jumps around under the pointer.
struct ChipView: View {
    static let width: CGFloat = 340
    static let cornerRadius: CGFloat = 16

    @ObservedObject var model: ChipModel
    @FocusState private var searchFocused: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ZStack {
                picker
                    .opacity(model.phase == .picking ? 1 : 0)
                    .allowsHitTesting(model.phase == .picking)
                overlay
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .background(VisualEffectBackground(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92, anchor: model.anchor)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.26, dampingFraction: 0.78)) { appeared = true }
            searchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ConvertAll")
        .onHover { model.isHovering = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                if model.files.count > 1 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-7))
                        .offset(x: -2, y: 1)
                }
                Image(nsImage: model.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
    }

    // MARK: Picking

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        if model.sections.count > 1 {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: ChipModel.columns),
                            spacing: 6
                        ) {
                            ForEach(section.actions) { action in
                                let requirement = model.requirement(for: action)
                                FormatPill(
                                    label: model.label(action),
                                    isHighlighted: model.highlighted == action,
                                    isMatch: model.isMatch(action),
                                    needsDownload: requirement != .ready,
                                    hint: hint(for: action, requirement),
                                    reduceMotion: reduceMotion
                                ) {
                                    model.run(action)
                                } onHover: { inside in
                                    // Hover only previews (the footnote); the keyboard selection stays put.
                                    if inside { model.hovered = action } else if model.hovered == action { model.hovered = nil }
                                }
                            }
                        }
                    }
                }
            }
            OptionsStrip(model: model)
            Divider().opacity(0.6)
            HStack(spacing: 6) {
                Text(model.footnote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .animation(nil, value: model.highlighted)
                Spacer(minLength: 4)
                if let update = model.update {
                    Button { model.installUpdate() } label: {
                        Label("Update to \(update.version.description)", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("A new version of ConvertAll is available. Installs and relaunches in a few seconds.")
                } else {
                    KeyHint(symbol: "↩", label: "Convert")
                    KeyHint(symbol: "⌘↩", label: "& Reveal")
                }
            }
        }
        .frame(minHeight: 170, alignment: .top)
    }

    private func hint(for action: ChipAction, _ requirement: Requirement) -> String {
        switch requirement {
        case .ready: model.blurb(action)
        case .mediaEngine: "\(model.blurb(action)). Downloads the free media engine once (\(MediaPack.downloadSizeText))."
        case .libreOffice: "\(model.blurb(action)). Needs LibreOffice (free)."
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Convert to… (type a format)", text: $model.query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($searchFocused)
                .accessibilityLabel("Search formats")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: Engine prompts / converting / done / failed

    @ViewBuilder private var overlay: some View {
        switch model.phase {
        case .picking:
            EmptyView()

        case .needs(let action, .mediaEngine):
            ResultMessage(
                symbol: "shippingbox.fill", tint: .accentColor,
                title: "One-time download",
                detail: "\(model.label(action)) uses FFmpeg, a free media engine (\(MediaPack.downloadSizeText)). It's saved once and works offline afterwards."
            ) {
                Button("Download & Continue") { model.installEngineAndRun() }
                    .keyboardShortcut(.defaultAction)
                Button("Back") { model.backToPicking() }
            }

        case .needs(let action, _):
            ResultMessage(
                symbol: "tablecells.fill", tint: .accentColor,
                title: "One-time download",
                detail: "Spreadsheets and presentations use LibreOffice's free document engine (\(OfficePack.downloadSizeText)). It's saved once and works offline afterwards."
            ) {
                Button("Download & Continue") { model.installEngineAndRun() }
                    .keyboardShortcut(.defaultAction)
                Button("I Have LibreOffice") { model.run(action) }
                    .help("Already installed LibreOffice yourself? ConvertAll will find it.")
                Button("Back") { model.backToPicking() }
            }

        case .installingEngine(let action, let progress):
            ProgressPanel(
                title: model.requirement(for: action) == .libreOffice ? "Downloading document pack…" : "Downloading media engine…",
                detail: "Then: \(action.verb.lowercased())",
                progress: progress
            )

        case .trimming:
            TrimPanel(model: model)

        case .converting(let action, let progress, let done, let total):
            ProgressPanel(
                title: "\(action.verb)…",
                detail: total > 1 ? "\(done) of \(total)" : nil,
                progress: progress,
                onCancel: model.cancelConversion
            )

        case .updating:
            ProgressPanel(
                title: "Updating ConvertAll…",
                detail: updateDetail,
                progress: { if case .downloading(let p) = model.updateState { return p }; return 0 }()
            )

        case .finished(let action, let outputs, let failures, let skipped):
            if outputs.isEmpty {
                ResultMessage(
                    symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: failureTitle(action),
                    detail: failures.first ?? "Something went wrong."
                ) {
                    Button("Try Another Format") { model.backToPicking() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                ResultMessage(
                    symbol: "checkmark.circle.fill", tint: .green,
                    title: outputs.count == 1
                        ? outputs[0].lastPathComponent
                        : "\(outputs.count) files converted to \(action.format.displayName)",
                    detail: finishedDetail(failures: failures, skipped: skipped)
                ) {
                    Button("Show in Finder", action: model.revealOutputs)
                        .keyboardShortcut(.defaultAction)
                    Button("Open", action: model.openOutputs)
                }
                .onDrag { NSItemProvider(contentsOf: outputs[0]) ?? NSItemProvider() }
                .help(outputs.count == 1 ? String("Drag the new file anywhere") : String())
            }

        case .unsupported(let message):
            ResultMessage(symbol: "questionmark.folder.fill", tint: .secondary, title: "Nothing to convert", detail: message) {
                Button("OK") { model.onClose() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failureTitle(_ action: ChipAction) -> String {
        switch action {
        case .compress: "Couldn't make it smaller"
        case .extractText: "Couldn't read any text"
        case .removeBackground: "Couldn't cut out the subject"
        case .combine: "Couldn't combine these files"
        case .convert(let f): "Couldn't convert to \(f.displayName)"
        }
    }

    private func finishedDetail(failures: [String], skipped: Int) -> String {
        var parts: [String] = []
        if !failures.isEmpty { parts.append("\(failures.count) couldn't be converted") }
        if skipped > 0 { parts.append("\(skipped) skipped (not convertible to this)") }
        if parts.isEmpty, model.clipboardMode {
            parts.append("Copied to the clipboard")
            parts.append(model.savingsText ?? "paste anywhere")
        } else if parts.isEmpty {
            parts.append("Saved next to the original")
            parts.append(model.savingsText ?? "drag me anywhere")
        }
        return parts.joined(separator: " · ")
    }

    private var updateDetail: String {
        switch model.updateState {
        case .failed(let message): message
        case .installing: "Installing — ConvertAll will reopen"
        default: model.update.map { "Version \($0.version.description)" } ?? ""
        }
    }
}

// MARK: - Pieces

private struct FormatPill: View {
    let label: String
    let isHighlighted: Bool
    let isMatch: Bool
    let needsDownload: Bool
    let hint: String
    let reduceMotion: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                if needsDownload {
                    Image(systemName: "arrow.down.circle")
                        .font(.footnote.weight(.semibold))
                        .opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor : Color.primary.opacity(hovering ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering && !isHighlighted ? 0.25 : 0.07), lineWidth: hovering ? 1 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
        // Non-matches fade but keep their place (the grid never reshuffles); they're out of
        // reach for clicks, keyboard and VoiceOver until the search matches them again.
        .opacity(isMatch ? 1 : 0.35)
        .allowsHitTesting(isMatch)
        .accessibilityHidden(!isMatch)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
        .animation(.easeOut(duration: 0.12), value: isMatch)
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityValue(needsDownload ? "needs a one-time download" : "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// Quality · Size · Metadata — compact menus under the grid. Defaults keep the
/// one-click flow; choices are remembered for next time.
private struct OptionsStrip: View {
    @ObservedObject var model: ChipModel

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(ConversionOptions.Quality.allCases, id: \.self) { q in
                    Button { model.options.quality = q } label: {
                        if model.options.quality == q { Label(q.title, systemImage: "checkmark") } else { Text(q.title) }
                    }
                }
            } label: {
                Text(model.options.quality.title)
            }
            .help("Quality: smaller files or better fidelity")
            .accessibilityLabel("Quality: \(model.options.quality.title)")

            Menu {
                Section("Dimensions") { sizeItems(ConversionOptions.Size.presets) }
                Section("File size") { sizeItems(ConversionOptions.Size.targetPresets) }
            } label: {
                Text(model.options.size.shortTitle)
            }
            .help("Resize, or aim for a maximum file size")
            .accessibilityLabel("Size: \(model.options.size.title)")

            Toggle(isOn: $model.options.stripMetadata) {
                Label("No metadata", systemImage: model.options.stripMetadata ? "eye.slash.fill" : "eye.slash")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .help(model.options.stripMetadata ? "Metadata will be removed (location, camera, author)" : "Remove location, camera and author details from the result")
            .accessibilityLabel("Remove metadata")

            Menu {
                Button { model.options.saveTo = nil } label: { check(model.options.saveTo == nil, "Next to the Original") }
                Divider()
                ForEach(SaveSpot.common, id: \.path) { spot in
                    Button { model.options.saveTo = spot.path } label: { check(model.options.saveTo == spot.path, spot.name) }
                }
                if let custom = model.options.saveTo, !SaveSpot.common.map(\.path).contains(custom) {
                    Button {} label: { check(true, (custom as NSString).lastPathComponent) }
                }
                Divider()
                Button("Choose Folder…") { model.chooseSaveFolder() }
            } label: {
                Label(model.options.saveTo.map { ($0 as NSString).lastPathComponent } ?? "Beside", systemImage: "folder")
            }
            .help("Where converted files are saved")
            .accessibilityLabel("Save to: \(model.options.saveTo.map { ($0 as NSString).lastPathComponent } ?? "next to the original")")

            if model.canTrim {
                Button { model.beginTrim() } label: {
                    Label(model.trim.map { "\(ChipModel.time($0.lowerBound))–\(ChipModel.time($0.upperBound))" } ?? "Trim",
                          systemImage: "timeline.selection")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(model.trim == nil ? Color.primary : Color.accentColor)
                .help("Keep only part of the clip")
            }

            Spacer(minLength: 0)
            if !model.options.isDefault {
                Button("Reset") { model.resetOptions() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Back to Balanced · Original size · keep metadata")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)  // they're menus: show it
        .controlSize(.small)
        .font(.subheadline)
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func check(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    @ViewBuilder private func sizeItems(_ sizes: [ConversionOptions.Size]) -> some View {
        ForEach(sizes, id: \.self) { size in
            Button { model.options.size = size } label: {
                if model.options.size == size { Label(size.title, systemImage: "checkmark") } else { Text(size.title) }
            }
        }
    }
}

/// Common "Save to" folders.
private enum SaveSpot {
    struct Spot { let name: String; let path: String }
    static var common: [Spot] {
        [(FileManager.SearchPathDirectory.desktopDirectory, "Desktop"), (.downloadsDirectory, "Downloads"),
         (.documentDirectory, "Documents"), (.picturesDirectory, "Pictures")]
            .compactMap { dir, name in FileManager.default.urls(for: dir, in: .userDomainMask).first.map { Spot(name: name, path: $0.path) } }
    }
}

/// Pick the part of a clip to keep: a two-handle range over the clip's length.
private struct TrimPanel: View {
    @ObservedObject var model: ChipModel

    var body: some View {
        let duration = model.mediaDuration ?? 1
        let range = model.trim ?? 0...duration
        VStack(spacing: 12) {
            Text("Trim").font(.headline).accessibilityAddTraits(.isHeader)
            RangeSlider(range: Binding(get: { range }, set: { model.trim = $0 }), bounds: 0...duration)
                .frame(height: 28)
                .padding(.horizontal, 6)
            HStack {
                Text(ChipModel.time(range.lowerBound))
                Spacer()
                Text("\(ChipModel.time(range.upperBound - range.lowerBound)) kept").foregroundStyle(.secondary)
                Spacer()
                Text(ChipModel.time(range.upperBound))
            }
            .font(.subheadline.monospacedDigit())
            HStack(spacing: 8) {
                Button("Reset") { model.endTrim(keep: false) }
                Button("Done") { model.endTrim(keep: true) }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

/// A slider with two handles (start and end).
private struct RangeSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - knob, 1)
            let span = max(bounds.upperBound - bounds.lowerBound, 0.001)
            let x = { (v: Double) in CGFloat((v - bounds.lowerBound) / span) * width }
            let value = { (px: CGFloat) in bounds.lowerBound + Double(min(max(px, 0), width) / width) * span }
            let minGap = span / 200

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4).padding(.horizontal, knob / 2)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(x(range.upperBound) - x(range.lowerBound), 0), height: 4)
                    .offset(x: x(range.lowerBound) + knob / 2)
                handle.offset(x: x(range.lowerBound))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("track")).onChanged { g in
                        range = min(value(g.location.x - knob / 2), range.upperBound - minGap)...range.upperBound
                    })
                handle.offset(x: x(range.upperBound))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("track")).onChanged { g in
                        range = range.lowerBound...max(value(g.location.x - knob / 2), range.lowerBound + minGap)
                    })
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(name: "track")
        }
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: knob, height: knob)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

/// Determinate progress (spinner until the first report) with an optional Cancel.
private struct ProgressPanel: View {
    let title: String
    let detail: String?
    let progress: Double
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if progress <= 0 { ProgressView().controlSize(.small) }
                Text(title).font(.body.weight(.medium))
            }
            if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .animation(.linear(duration: 0.2), value: progress)
            }
            HStack(spacing: 6) {
                if progress > 0 { Text("\(Int(progress * 100))%").monospacedDigit() }
                if let detail, !detail.isEmpty {
                    if progress > 0 { Text("·") }
                    Text(detail)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .help("Stop converting  (esc)")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

private struct PressableStyle: ButtonStyle {
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct KeyHint: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label).font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct ResultMessage<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .scaleEffect(popped || reduceMotion ? 1 : 0.4)
                .opacity(popped ? 1 : 0)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack(spacing: 8) { actions() }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.6).delay(0.05)) { popped = true }
        }
    }
}

/// Native translucent material, clipped to the chip's rounded shape (so the window
/// shadow follows the corners too).
struct VisualEffectBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
#endif
