#if os(macOS)
import AppKit
import SwiftUI

/// Borderless floating panel that can take keyboard focus (for the search field)
/// and floats over every app and Space, including full-screen ones.
final class ChipPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows one chip at a time next to the pointer and wires up keyboard and
/// click-outside-to-dismiss behaviour.
final class ChipController {
    static let shared = ChipController()

    /// Gap between the pointer and the chip's nearest corner.
    private let gap: CGFloat = 10

    private var panel: ChipPanel?
    private var model: ChipModel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    var onDidClose: () -> Void = {}
    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameters:
    ///   - clipboard: the result is copied to the clipboard (⌥⌘V flow).
    ///   - actionID: start this action right away (Finder menu presets), e.g. "convert-png".
    func present(_ urls: [URL], at point: NSPoint = NSEvent.mouseLocation, clipboard: Bool = false, run actionID: String? = nil) {
        close(animated: false)
        guard ChipModel.Selection.isHeavy(urls) else {
            show(.load(urls), at: point, clipboard: clipboard, run: actionID)
            return
        }
        // Big folders take a moment to scan: show that something is happening right away,
        // and read the files off the main thread so the pointer never beach-balls.
        let token = UUID()
        loadingToken = token
        showLoading(at: point)
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = ChipModel.Selection.load(urls)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadingToken == token else { return }
                self.show(loaded, at: point, clipboard: clipboard, run: actionID)
            }
        }
    }

    /// Identifies the selection being read, so a newer `present` or a close discards it.
    private var loadingToken: UUID?

    private func showLoading(at point: NSPoint) {
        let hosting = NSHostingView(rootView: ReadingChip())
        let size = hosting.fittingSize
        let panel = ChipPanel(contentRect: placement(for: size, near: point).0)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        self.panel = panel
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "Reading files…", .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    private func show(_ loaded: ChipModel.Selection, at point: NSPoint, clipboard: Bool, run actionID: String?) {
        close(animated: false)
        let model = ChipModel(loaded: loaded)
        model.clipboardMode = clipboard
        let hosting = NSHostingView(rootView: ChipView(model: model))
        let size = hosting.fittingSize
        let (frame, anchor) = placement(for: size, near: point)
        model.anchor = anchor
        model.onClose = { [weak self] in self?.close() }

        let panel = ChipPanel(contentRect: frame)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.model = model
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { panel.invalidateShadow() }

        if let actionID, let action = model.action(withID: actionID) {
            DispatchQueue.main.async { model.run(action) }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.model, event.window === self.panel else { return event }
            return model.handleKey(event) ? nil : event
        }
        // Clicking anywhere else dismisses the chip, like a menu — unless it's busy (converting,
        // downloading); then it keeps floating so you can keep working while it finishes.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, let model = self.model, !model.isBusy, !model.presentingPanel else { return }
            self.close()
        }
    }

    func close(animated: Bool = true) {
        loadingToken = nil
        guard let panel else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil
        self.panel = nil
        model = nil

        let finish = { [weak self] in
            panel.orderOut(nil)
            self?.onDidClose()
        }
        guard animated else { return finish() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: finish)
    }

    /// Below-right of the pointer like a context menu; flips left/up near screen edges.
    private func placement(for size: NSSize, near p: NSPoint) -> (NSRect, UnitPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var anchorX: CGFloat = 0, anchorY: CGFloat = 0  // SwiftUI: y = 0 is the top edge
        var x = p.x + gap
        if x + size.width > bounds.maxX { x = p.x - gap - size.width; anchorX = 1 }
        var y = p.y - gap - size.height
        if y < bounds.minY { y = p.y + gap; anchorY = 1 }

        x = min(max(x, bounds.minX + 4), bounds.maxX - size.width - 4)
        y = min(max(y, bounds.minY + 4), bounds.maxY - size.height - 4)
        return (NSRect(origin: NSPoint(x: x, y: y), size: size), UnitPoint(x: anchorX, y: anchorY))
    }
}

/// Placeholder shown while a big selection is being read.
private struct ReadingChip: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading files…").font(.callout)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
#endif
