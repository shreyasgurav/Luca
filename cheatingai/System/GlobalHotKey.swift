import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    typealias HotKeyHandler = () -> Void

    private let keyCode: UInt32
    private let modifiers: NSEvent.ModifierFlags
    private let handler: HotKeyHandler

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping HotKeyHandler) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func register() {
        var hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "CHAI".utf8.reduce(0) { ($0 << 8) + UInt32($1) })), id: 1)

        let modifiersCarbon = carbonFlags(from: modifiers)

        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            var hkCom = EventHotKeyID()
            let status = GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkCom)
            if status == noErr {
                // Invoke the stored Swift closure
                if let userData = userData {
                    let unmanaged = Unmanaged<GlobalHotKey>.fromOpaque(userData)
                    let hotkey = unmanaged.takeUnretainedValue()
                    hotkey.handler()
                }
            }
            return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))], Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let status = RegisterEventHotKey(keyCode, modifiersCarbon, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("Failed to register hotkey: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}


