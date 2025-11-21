import AppKit
import SwiftUI

/// Manages a floating tooltip window that can appear outside the main overlay bounds
final class TooltipWindowManager: ObservableObject {
    static let shared = TooltipWindowManager()
    
    private var tooltipWindow: NSPanel?
    private var hostingController: NSHostingController<TooltipView>?
    private var mouseMoveMonitor: Any?
    private weak var monitoredParentWindow: NSWindow?
    private var pendingShowWorkItem: DispatchWorkItem?
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillMove(_:)),
            name: NSWindow.willMoveNotification,
            object: nil
        )
    }
    
    @objc private func handleWindowWillMove(_ notification: Notification) {
        // Hide tooltip when any window starts moving
        hideTooltip()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func showTooltip(text: String, at position: CGPoint, parentWindow: NSWindow, isLeftSide: Bool = false, placeBelow: Bool = false) {
        // Cancel any pending request and hide any visible tooltip first
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        hideTooltip()

        // Schedule showing after 1 second of hover
        let workItem = DispatchWorkItem { [weak self] in
            self?.presentTooltip(text: text, at: position, parentWindow: parentWindow, isLeftSide: isLeftSide, placeBelow: placeBelow)
        }
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func presentTooltip(text: String, at position: CGPoint, parentWindow: NSWindow, isLeftSide: Bool = false, placeBelow: Bool = false) {
        // Clear pending since we're presenting now
        pendingShowWorkItem = nil

        // Create tooltip window (smaller universal size)
        tooltipWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 64, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        guard let tooltipWindow = tooltipWindow else { return }
        
        // Configure tooltip window
        tooltipWindow.level = .floating
        tooltipWindow.isOpaque = false
        tooltipWindow.backgroundColor = NSColor.clear
        tooltipWindow.hasShadow = false
        tooltipWindow.acceptsMouseMovedEvents = false
        tooltipWindow.ignoresMouseEvents = true
        tooltipWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        tooltipWindow.isReleasedWhenClosed = false
        tooltipWindow.isExcludedFromWindowsMenu = true
        tooltipWindow.canBecomeVisibleWithoutLogin = true
        tooltipWindow.sharingType = AppConfig.isVisibleInScreenCapture ? .readOnly : .none
        
        // Ensure tooltip doesn't interfere with parent window hover detection
        tooltipWindow.hidesOnDeactivate = false
        
        // Create hosting controller with tooltip view
        hostingController = NSHostingController(rootView: TooltipView(text: text))
        tooltipWindow.contentViewController = hostingController
        
        // Configure hosting controller to remove any default styling
        if let hosting = hostingController {
            hosting.view.wantsLayer = true
            hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
            hosting.view.layer?.cornerRadius = 0
            hosting.view.layer?.masksToBounds = true
        }
        
        // Position tooltip based on side
        let tooltipFrame: CGRect
        if isLeftSide {
            // Position tooltip below the logo (left side)
            tooltipFrame = CGRect(
                x: position.x - 24,
                y: position.y - 58,
                width: 80,
                height: 32
            )
        } else if placeBelow {
            // Position tooltip centered below the triggering button (Listen button) - moved slightly right
            tooltipFrame = CGRect(
                x: position.x - 8,  // Moved 4px right (was -12, now -8)
                y: position.y - 58,
                width: 64,
                height: 32
            )
        } else {
            // Position tooltip to the right of the button (hide button) - moved slightly up
            tooltipFrame = CGRect(
                x: position.x + 55,
                y: position.y - 17,  // Moved 4px up (was -21, now -25)
                width: 50,
                height: 32
            )
        }
        tooltipWindow.setFrame(tooltipFrame, display: true)
        
        // Add as child window to parent
        parentWindow.addChildWindow(tooltipWindow, ordered: .above)
        
        // Show with animation
        tooltipWindow.alphaValue = 0
        tooltipWindow.makeKeyAndOrderFront(nil)
        tooltipWindow.orderFrontRegardless()
        
        // Fade in animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            tooltipWindow.animator().alphaValue = 1.0
        }

        // Start monitoring mouse to auto-hide when it leaves the overlay area
        startMouseLeaveMonitor(for: parentWindow)
    }
    
    func hideTooltip() {
        // Cancel any pending show
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        
        guard let tooltipWindow = tooltipWindow else { return }
        
        // Fade out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            tooltipWindow.animator().alphaValue = 0.0
        }) {
            // Remove from parent and close
            tooltipWindow.parent?.removeChildWindow(tooltipWindow)
            tooltipWindow.orderOut(nil)
            self.tooltipWindow = nil
            self.hostingController = nil
            self.stopMouseLeaveMonitor()
        }
    }

    // MARK: - Mouse leave monitoring
    private func startMouseLeaveMonitor(for parentWindow: NSWindow) {
        stopMouseLeaveMonitor()
        monitoredParentWindow = parentWindow
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            guard let self = self,
                  let window = self.monitoredParentWindow,
                  let screen = window.screen else { return }
            let mouseLocation = NSEvent.mouseLocation
            // Convert to the screen of the window to compare properly
            // Expand frame slightly to be forgiving
            let frame = window.frame.insetBy(dx: -12, dy: -12)
            if !frame.contains(mouseLocation) {
                self.hideTooltip()
            }
        }
    }
    
    private func stopMouseLeaveMonitor() {
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
        monitoredParentWindow = nil
    }
    
    // MARK: - Screen Capture Visibility Management
    
    func updateSharingType() {
        let sharingType: NSWindow.SharingType = AppConfig.isVisibleInScreenCapture ? .readOnly : .none
        tooltipWindow?.sharingType = sharingType
        print("🔄 Updated tooltip sharing type: \(sharingType == .readOnly ? "visible" : "hidden")")
    }
}

/// SwiftUI view for the tooltip content
struct TooltipView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(1.0) // Prevent autoscaling so all tooltips use identical text size
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
            )
    }
}
