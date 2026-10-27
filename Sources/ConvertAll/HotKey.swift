#if os(macOS)
import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut (Carbon's RegisterEventHotKey: no Accessibility permission needed).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Default: ⌥⌘V — "paste, converted".
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &type, me, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4356_414C), id: 1)  // 'CVAL'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
#endif
