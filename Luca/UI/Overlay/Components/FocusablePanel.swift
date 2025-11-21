import AppKit

// Custom NSPanel subclass to handle text input properly
class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
}
