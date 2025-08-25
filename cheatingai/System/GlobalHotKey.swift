import AppKit
import Carbon.HIToolbox

// PRODUCTION-READY: Enhanced GlobalHotKey Manager
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    
    private var hotKeys: [GlobalHotKey] = []
    private var eventHandler: EventHandlerRef?
    
    private init() {}
    
    func registerHotKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) -> GlobalHotKey? {
        let hotKey = GlobalHotKey(keyCode: keyCode, modifiers: modifiers, handler: handler)
        
        // Install global event handler only once
        if eventHandler == nil {
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, theEvent, userData) -> OSStatus in
                    GlobalHotKeyManager.shared.handleHotKeyEvent(theEvent)
                    return noErr
                },
                1,
                [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))],
                nil,
                &GlobalHotKeyManager.shared.eventHandler
            )
            
            if status != noErr {
                print("❌ Failed to install global event handler: \(status)")
                return nil
            }
        }
        
        if hotKey.register() {
            hotKeys.append(hotKey)
            print("✅ Registered hotkey: \(keyCode) + \(modifiers)")
            return hotKey
        }
        
        return nil
    }
    
    func unregisterAll() {
        hotKeys.forEach { $0.unregister() }
        hotKeys.removeAll()
        
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        if status == noErr {
            // Find matching hotkey and execute handler
            if let hotKey = hotKeys.first(where: { $0.hotKeyID.id == hotKeyID.id }) {
                DispatchQueue.main.async {
                    hotKey.handler()
                }
            }
        }
        
        return noErr
    }
    
    // Diagnostics and validation
    func validateHotKeyConflicts() -> [String] {
        var conflicts: [String] = []
        
        // Check for common system hotkey conflicts
        let systemHotKeys: [(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, name: String)] = [
            (UInt32(kVK_Space), [.command], "Spotlight"),
            (UInt32(kVK_Tab), [.command], "App Switcher"),
            (UInt32(kVK_ANSI_W), [.command], "Close Window"),
            (UInt32(kVK_ANSI_Q), [.command], "Quit App"),
            (UInt32(kVK_ANSI_N), [.command], "New Window")
        ]
        
        for hotKey in hotKeys {
            for systemHotKey in systemHotKeys {
                if hotKey.keyCode == systemHotKey.keyCode && hotKey.modifiers == systemHotKey.modifiers {
                    conflicts.append("⚠️ Hotkey conflicts with system function: \(systemHotKey.name)")
                }
            }
        }
        
        return conflicts
    }
    
    func printDiagnostics() {
        print("🔍 GlobalHotKey Diagnostics:")
        print("   Registered hotkeys: \(hotKeys.count)")
        print("   Event handler installed: \(eventHandler != nil)")
        
        for (index, hotKey) in hotKeys.enumerated() {
            print("   [\(index + 1)] KeyCode: \(hotKey.keyCode), Modifiers: \(hotKey.modifiers)")
        }
        
        let conflicts = validateHotKeyConflicts()
        if !conflicts.isEmpty {
            conflicts.forEach { print($0) }
        } else {
            print("   ✅ No system conflicts detected")
        }
    }
}

// Enhanced GlobalHotKey class
final class GlobalHotKey {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    let handler: () -> Void
    let hotKeyID: EventHotKeyID
    
    private var hotKeyRef: EventHotKeyRef?
    
    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        
        // Generate unique ID based on keycode and modifiers
        var hasher = Hasher()
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
        let uniqueID = UInt32(abs(hasher.finalize()) % 65535)
        
        self.hotKeyID = EventHotKeyID(
            signature: OSType(UInt32(truncatingIfNeeded: "NOVA".utf8.reduce(0) { ($0 << 8) + UInt32($1) })),
            id: uniqueID
        )
    }
    
    @discardableResult
    func register() -> Bool {
        let carbonModifiers = carbonFlags(from: modifiers)
        
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("❌ Failed to register hotkey \(keyCode): \(status)")
            return false
        }
        
        return true
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
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
