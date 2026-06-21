import Foundation
import Carbon.HIToolbox

/// Thin wrapper over Carbon RegisterEventHotKey for a single system-wide hotkey.
/// Registration needs no Accessibility permission. If the combo is already taken,
/// `isRegistered` is false and the handler simply never fires.
@MainActor
public final class GlobalHotKey {
    public private(set) var isRegistered = false

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private let handler: () -> Void
    private let id: UInt32

    // Carbon delivers hotkey events on the main run loop, and init/deinit run on
    // the main actor, so this registry is only ever touched from the main thread —
    // the nonisolated(unsafe) statics are safe by that invariant.
    // Maps a hotkey id to its instance so the C event callback can dispatch.
    nonisolated(unsafe) private static var registry: [UInt32: GlobalHotKey] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    public init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.registry[self.id] = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let target = GlobalHotKey.registry[hkID.id] {
                DispatchQueue.main.async { target.handler() }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        let hkID = EventHotKeyID(signature: OSType(0x4D454D45), id: id)  // 'MEME'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        GlobalHotKey.registry[id] = nil
    }
}
