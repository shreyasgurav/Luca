import SwiftUI
import AppKit

/// Native window drag area that uses macOS performDrag for smooth system-level dragging
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return DragHostingView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DragHostingView: NSView {
    private var mouseDownPoint: NSPoint = .zero
    private var hasDragged: Bool = false
    private let dragThreshold: CGFloat = 3.0 // Minimum distance to consider it a drag
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow mouse down to be captured for dragging
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        hasDragged = false
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        let distance = sqrt(pow(currentPoint.x - mouseDownPoint.x, 2) + pow(currentPoint.y - mouseDownPoint.y, 2))
        
        if distance > dragThreshold {
            hasDragged = true
            guard let window = self.window else { return }
            // This uses native window dragging. Child windows follow the parent automatically.
            window.performDrag(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        // Reset drag state
        hasDragged = false
        mouseDownPoint = .zero
    }
    
    // Helper method to check if a drag occurred (for buttons to use)
    static var isDragging: Bool = false
    
    private func updateDragState(_ dragging: Bool) {
        DragHostingView.isDragging = dragging
    }
}
