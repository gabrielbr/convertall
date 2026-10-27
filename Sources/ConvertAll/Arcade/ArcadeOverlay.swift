#if os(macOS)
import AppKit
import SwiftUI

/// A transparent, click-through window covering the screen under the pointer — the arcade's stage.
final class ArcadeOverlayWindow: NSPanel {
    init(director: ArcadeDirector) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: ArcadeStage(director: director))
    }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.frame, frame != self.frame { setFrame(frame, display: true) }
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
}

private struct ArcadeStage: View {
    @ObservedObject var director: ArcadeDirector

    var body: some View {
        ZStack {
            if let banner = director.banner {
                BannerView(banner: banner, reduceMotion: director.reduceMotion)
                    .id(banner.id)
                    .transition(.opacity)
            }
            if director.showingCombo {
                ComboView(hits: director.combo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 60)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            PopIn(visible: director.popInVisible, reduceMotion: director.reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .animation(.easeOut(duration: 0.2), value: director.banner)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: director.showingCombo)
        .allowsHitTesting(false)
    }
}

/// Big centred title: slams in from huge, shakes, holds.
private struct BannerView: View {
    let banner: ArcadeDirector.Banner
    let reduceMotion: Bool
    @State private var landed = false
    @State private var shake: CGFloat = 0

    private var colors: [Color] {
        switch banner.style {
        case .ko: [Color(red: 1, green: 0.85, blue: 0.85), .red, Color(red: 0.45, green: 0, blue: 0)]
        case .round: [.white, Color(red: 0.75, green: 0.85, blue: 1), Color(red: 0.2, green: 0.35, blue: 0.9)]
        case .convertly, .cheat: [Color(red: 1, green: 0.97, blue: 0.6), .yellow, .orange, .red, Color(red: 0.5, green: 0.05, blue: 0)]
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Text(banner.text)
                .font(.system(size: banner.text.count > 10 ? 110 : 150, weight: .black, design: .serif))
                .italic()
                .tracking(-2)
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                // Thick dark outline + drop shadow, the 90s way: stacked hard shadows.
                .shadow(color: .black, radius: 0, x: 3, y: 3)
                .shadow(color: .black, radius: 0, x: -3, y: -3)
                .shadow(color: .black, radius: 0, x: 3, y: -3)
                .shadow(color: .black, radius: 0, x: -3, y: 3)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 10, y: 12)
                .shadow(color: colors[colors.count / 2].opacity(0.8), radius: 30)
            if let subtitle = banner.subtitle {
                Text(subtitle)
                    .font(.custom(ArcadeAssets.fontName, size: 34))
                    .foregroundStyle(.white)
                    .shadow(color: .red, radius: 0, x: 4, y: 4)
                    .shadow(color: .black, radius: 0, x: 6, y: 6)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.3)
        .padding(.horizontal, 40)
        .scaleEffect(reduceMotion || landed ? 1 : 2.6)
        .opacity(landed ? 1 : 0)
        .offset(x: shake)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(stiffness: 520, damping: 24)) { landed = true }
            guard !reduceMotion else { return }
            // Impact shake once it lands.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                for x in [14.0, -12, 9, -6, 3, 0] {
                    withAnimation(.linear(duration: 0.04)) { shake = x }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
            }
        }
    }
}

private struct ComboView: View {
    let hits: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(hits)")
                .font(.custom(ArcadeAssets.fontName, size: 64))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
            Text("HIT COMBO!")
                .font(.custom(ArcadeAssets.fontName, size: 24))
                .foregroundStyle(.white)
        }
        .shadow(color: .black, radius: 0, x: 4, y: 4)
        .id(hits)
        .transition(.scale(scale: 1.6).combined(with: .opacity))
    }
}

/// The corner pop-in: peeks in from the bottom-right edge, then ducks back out.
private struct PopIn: View {
    let visible: Bool
    let reduceMotion: Bool

    var body: some View {
        Group {
            if let image = ArcadeAssets.image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PixelMascot()
            }
        }
        .frame(height: 280)
        .offset(x: visible || reduceMotion ? 0 : 340, y: visible || reduceMotion ? 0 : 120)
        .opacity(reduceMotion ? (visible ? 1 : 0) : 1)
        .animation(.easeOut(duration: 0.18), value: visible)
    }
}

/// Original pixel-art mascot (a happy file with shades) — the default pop-in.
private struct PixelMascot: View {
    // . transparent  K outline  W paper  F fold  G glasses  S shine  M mouth
    private static let art = [
        "..KKKKKKKKK.....",
        "..KWWWWWWWKK....",
        "..KWWWWWWWKFK...",
        "..KWWWWWWWKFFK..",
        "..KWWWWWWWKKKKK.",
        "..KWWWWWWWWWWWK.",
        "..KGGGGGWGGGGGK.",
        "..KGSGGGKGSGGGK.",
        "..KWGGGWWWGGGWK.",
        "..KWWWWWWWWWWWK.",
        "..KWWMWWWWWMWWK.",
        "..KWWWMMMMMWWWK.",
        "..KWWWWWWWWWWWK.",
        "..KWWWWWWWWWWWK.",
        "..KKKKKKKKKKKKK.",
        "................",
    ]

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width, size.height) / 16
            for (y, row) in Self.art.enumerated() {
                for (x, ch) in row.enumerated() {
                    let color: Color? = switch ch {
                    case "K": .black
                    case "W": .white
                    case "F": Color(white: 0.8)
                    case "G": Color(red: 0.1, green: 0.1, blue: 0.25)
                    case "S": .cyan
                    case "M": .red
                    default: nil
                    }
                    if let color {
                        context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(color))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
#endif
