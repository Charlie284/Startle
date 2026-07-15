import Carbon
import Foundation

@MainActor
public final class EmergencyShortcutManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<EmergencyShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.action() }
            return noErr
        }, 1, &type, pointer, &handler)
        let id = EventHotKeyID(signature: OSType(0x53545254), id: 1) // STRT
        RegisterEventHotKey(UInt32(kVK_Escape), UInt32(cmdKey | optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
