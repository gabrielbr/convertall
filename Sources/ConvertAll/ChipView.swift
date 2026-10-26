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
        .scaleEffect(appeared ? 1 : 0.92, anchor: model.anchor)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) { appeared = true }
            searchFocused = true
        }
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
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close  (esc)")
        }
    }

    // MARK: Picking

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: ChipModel.columns),
                spacing: 6
            ) {
                ForEach(model.formats) { format in
                    FormatPill(
                        format: format,
                        isHighlighted: model.highlighted == format,
                        isMatch: model.isMatch(format),
                        isAvailable: model.isAvailable(format),
                        hint: model.isAvailable(format) ? format.blurb : ImageConverter.installHint(for: format)
                    ) {
                        model.convert(format)
                    } onHover: {
                        model.highlighted = format
                    }
                }
            }
            Divider().opacity(0.6)
            HStack(spacing: 6) {
                Text(model.footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .animation(nil, value: model.highlighted)
                Spacer(minLength: 4)
                KeyHint(symbol: "↩", label: "Convert")
                KeyHint(symbol: "⌘↩", label: "& Reveal")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Convert to…  type a format", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: Converting / done / failed

    @ViewBuilder private var overlay: some View {
        switch model.phase {
        case .picking:
            EmptyView()

        case .converting(let format, let done, let total):
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Converting to \(format.displayName)…")
                        .font(.system(size: 13, weight: .medium))
                }
                if total > 1 {
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(width: 180)
                    Text("\(done) of \(total)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

        case .finished(let format, let outputs, let failures):
            if outputs.isEmpty {
                ResultMessage(
                    symbol: "exclamationmark.triangle.fill", tint: .orange,
                    title: "Couldn't convert to \(format.displayName)",
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
                        : "\(outputs.count) images converted to \(format.displayName)",
                    detail: failures.isEmpty
                        ? "Saved next to the original · drag me anywhere"
                        : "\(failures.count) couldn't be converted"
                ) {
                    Button("Show in Finder", action: model.revealOutputs)
                        .keyboardShortcut(.defaultAction)
                    Button("Open", action: model.openOutputs)
                }
                .onDrag { NSItemProvider(contentsOf: outputs[0]) ?? NSItemProvider() }
                .help(outputs.count == 1 ? String("Drag the new file anywhere") : String())
            }

        case .unsupported(let message):
            ResultMessage(symbol: "photo.badge.exclamationmark", tint: .secondary, title: "Nothing to convert", detail: message) {
                Button("OK") { model.onClose() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Pieces

private struct FormatPill: View {
    let format: ImageFormat
    let isHighlighted: Bool
    let isMatch: Bool
    let isAvailable: Bool
    let hint: String?
    let action: () -> Void
    let onHover: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(format.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if !isAvailable {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .foregroundStyle(isHighlighted && isAvailable ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isHighlighted && !isAvailable ? Color.accentColor : Color.primary.opacity(0.07),
                                  lineWidth: isHighlighted && !isAvailable ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(!isMatch ? 0.25 : (isAvailable ? 1 : 0.5))
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
        .animation(.easeOut(duration: 0.12), value: isMatch)
        .onHover { inside in
            hovering = inside
            if inside { onHover() }
        }
        .help(hint ?? "")
    }

    private var fill: Color {
        if isHighlighted && isAvailable { return .accentColor }
        return Color.primary.opacity(hovering ? 0.10 : 0.05)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct KeyHint: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
    }
}

private struct ResultMessage<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions
    @State private var popped = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .scaleEffect(popped ? 1 : 0.4)
                .opacity(popped ? 1 : 0)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 8) { actions() }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.05)) { popped = true }
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
