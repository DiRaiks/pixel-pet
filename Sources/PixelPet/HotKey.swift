import Carbon

/// A global keyboard shortcut via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// `keyCode` is a virtual key code (kVK_*), `modifiers` Carbon flags (controlKey | optionKey ...).
    init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        self.id = id
        Self.actions[id] = action
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5050_4554), id: id) // 'PPET'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("PixelPet: hotkey \(id) not registered (\(status)), probably taken by another app") }
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let id = hotKey.id
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { HotKey.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
        if status == noErr {
            handlerInstalled = true
        } else {
            NSLog("PixelPet: hotkey handler not installed (\(status))")
        }
    }
}
