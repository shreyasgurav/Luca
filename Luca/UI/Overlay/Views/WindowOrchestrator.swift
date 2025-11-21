import AppKit
import SwiftUI
import Combine

/// Multi-window orchestrator with bulletproof synchronization
final class WindowOrchestrator: NSObject {
    static let shared = WindowOrchestrator()
    
    // MARK: - Window References
    var buttonsWindow: FocusablePanel?
    var chatWindow: FocusablePanel?
    var listenWindow: FocusablePanel?
    
    // MARK: - Fixed Dimensions
    private let buttonsSize = CGSize(width: 320, height: 36)
    private let chatSize = CGSize(width: 500, height: 300)
    private let listenSize = CGSize(width: 320, height: 300)
    
    // MARK: - State Management
    private var lastPosition: CGPoint?
    private var wasChatVisible: Bool = false
    private var wasListenVisible: Bool = false
    
    // MARK: - Synchronization (CRITICAL)
    private let windowQueue = DispatchQueue(label: "com.luca.windowOrchestrator", qos: .userInteractive)
    private var isTransitioning = false
    private var isHiding = false // Prevents hide operations from overlapping
    private var pendingChatReshow = false // Prevents recursive asyncAfter stacking
    private var pendingListenReshow = false // Prevents recursive asyncAfter stacking
    
    // MARK: - Conversation Store
    let conversationStore = ConversationStore()
    
    // MARK: - Background Services
    private var backgroundMainChatView: MainChatView?
    private var backgroundWindow: NSWindow?
    
    private override init() {
        super.init()
        setupNotifications()
        setupBackgroundServices()
    }
    
    // MARK: - Background Services Setup
    
    private func setupBackgroundServices() {
        backgroundMainChatView = MainChatView(
            conversationStore: conversationStore,
            onAskQuestion: { [weak self] in
                self?.showChat()
            },
            onHide: { [weak self] in
                self?.hideAll()
            }
        )
        
        backgroundWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundWindow?.isOpaque = false
        backgroundWindow?.backgroundColor = NSColor.clear
        backgroundWindow?.level = .floating
        backgroundWindow?.orderOut(nil)
        backgroundWindow?.isReleasedWhenClosed = false
        
        let hostingController = NSHostingController(rootView: backgroundMainChatView!)
        backgroundWindow?.contentViewController = hostingController
    }
    
    // MARK: - Window Creation
    
    func createButtonsWindow() -> FocusablePanel {
        let panel = FocusablePanel(
            contentRect: CGRect(origin: .zero, size: buttonsSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configurePanel(panel, isDraggable: true)
        
        let hostingController = NSHostingController(rootView: ButtonsPanelView())
        panel.contentViewController = hostingController
        
        return panel
    }
    
    func createChatWindow() -> FocusablePanel {
        let panel = FocusablePanel(
            contentRect: CGRect(origin: .zero, size: chatSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configurePanel(panel, isDraggable: false)
        
        let hostingController = NSHostingController(rootView: ChatPanelView(conversationStore: conversationStore))
        panel.contentViewController = hostingController
        
        return panel
    }
    
    func createListenWindow() -> FocusablePanel {
        let panel = FocusablePanel(
            contentRect: CGRect(origin: .zero, size: listenSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configurePanel(panel, isDraggable: false)
        
        let hostingController = NSHostingController(rootView: ListenPanelView())
        panel.contentViewController = hostingController
        
        return panel
    }
    
    // MARK: - Child Window Management (BULLETPROOF)
    
    private func attachChild(_ child: FocusablePanel, completion: (() -> Void)? = nil) {
        guard let parent = buttonsWindow else {
            print("⚠️ Cannot attach child - no parent window")
            completion?()
            return
        }
        
        // CRITICAL: Check if already attached to THIS parent
        if child.parent == parent {
            print("ℹ️ Child already attached, skipping")
            completion?()
            return
        }
        
        // If attached to different parent, detach first
        if let oldParent = child.parent {
            print("🔄 Detaching from old parent before reattaching")
            oldParent.removeChildWindow(child)
        }
        
        // Ensure consistent properties
        child.collectionBehavior = parent.collectionBehavior
        child.level = parent.level
        child.isReleasedWhenClosed = false
        
        // Attach to parent
        parent.addChildWindow(child, ordered: .below)
        print("✅ Child window attached")
        
        // Wait one run loop for AppKit to finalize attachment
        DispatchQueue.main.async {
            completion?()
        }
    }
    
    private func detachChild(_ child: FocusablePanel) {
        guard child.parent != nil else {
            print("ℹ️ Child already detached, skipping")
            return
        }
        buttonsWindow?.removeChildWindow(child)
        print("✅ Child window detached")
    }
    
    // MARK: - Panel Configuration
    
    private func configurePanel(_ panel: FocusablePanel, isDraggable: Bool = true) {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.makeFirstResponder(nil)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = isDraggable
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = AppConfig.isVisibleInScreenCapture ? .readOnly : .none
        panel.isExcludedFromWindowsMenu = true
        panel.canBecomeVisibleWithoutLogin = true
        
        if let hosting = panel.contentViewController as? NSHostingController<AnyView> {
            if #available(macOS 13.0, *) { 
                hosting.sizingOptions = [] 
            }
            hosting.view.translatesAutoresizingMaskIntoConstraints = true
            hosting.view.autoresizingMask = [.width, .height]
            hosting.view.frame = panel.contentView?.bounds ?? .zero
        }
    }
    
    // MARK: - Window Management (ROBUST)
    
    func showButtons() {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if self.buttonsWindow == nil {
                    self.buttonsWindow = self.createButtonsWindow()
                    print("🆕 Created buttons window")
                }
                
                guard let panel = self.buttonsWindow else { return }
                
                // Position before showing
                self.positionButtonsWindow()
                
                // Show window
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.level = .floating
                panel.alphaValue = 1.0
                panel.makeKeyAndOrderFront(nil)
                panel.orderFrontRegardless()
                
                print("✅ Buttons window visible")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func showChat(with text: String = "", expanded: Bool = false) {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prevent overlapping transitions
            guard !self.isTransitioning else {
                print("⏳ Chat show skipped - transition in progress")
                return
            }
            
            self.isTransitioning = true
            
            DispatchQueue.main.async {
                // Ensure buttons window exists and is visible
                if self.buttonsWindow == nil || self.buttonsWindow?.isVisible != true {
                    print("📍 Showing buttons first before chat")
                    self.showButtons()
                    // Wait for buttons to be ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showChat(with: text, expanded: expanded)
                    }
                    self.isTransitioning = false
                    return
                }
                
                if self.chatWindow == nil {
                    self.chatWindow = self.createChatWindow()
                    print("🆕 Created chat window")
                }
                
                guard let panel = self.chatWindow else {
                    self.isTransitioning = false
                    return
                }
                
                // Position BEFORE attaching (prevents visible jump)
                self.positionChatWindow()
                
                // Attach child with completion handler
                self.attachChild(panel) {
                    // Re-position after attachment (ensures correct coordinates)
                    self.positionChatWindow()
                    
                    // Fade in animation
                    panel.alphaValue = 0.0
                    panel.makeKeyAndOrderFront(nil)
                    panel.orderFrontRegardless()
                    
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        context.allowsImplicitAnimation = true
                        panel.animator().alphaValue = 1.0
                    } completionHandler: {
                        self.isTransitioning = false
                        print("✅ Chat window visible")
                    }
                    
                    // Reposition other visible panels
                    self.repositionAllVisiblePanels(animated: true)
                    
                    // Process text if provided
                    if !text.isEmpty {
                        self.conversationStore.appendUser(text)
                        MessageProcessor.shared.processMessage(
                            text: text,
                            conversationStore: self.conversationStore,
                            requestId: UUID(),
                            onComplete: {
                                OverlayStateManager.shared.endInputCooldown()
                            }
                        )
                    }
                }
            }
        }
    }
    
    func showListen() {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.isTransitioning else {
                print("⏳ Listen show skipped - transition in progress")
                return
            }
            
            self.isTransitioning = true
            
            DispatchQueue.main.async {
                // Ensure buttons window exists
                if self.buttonsWindow == nil || self.buttonsWindow?.isVisible != true {
                    print("📍 Showing buttons first before listen")
                    self.showButtons()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showListen()
                    }
                    self.isTransitioning = false
                    return
                }
                
                if self.listenWindow == nil {
                    self.listenWindow = self.createListenWindow()
                    print("🆕 Created listen window")
                }
                
                guard let panel = self.listenWindow else {
                    self.isTransitioning = false
                    return
                }
                
                // Position before attaching
                self.positionListenWindow()
                
                self.attachChild(panel) {
                    // Re-position after attachment
                    self.positionListenWindow()
                    
                    panel.alphaValue = 0.0
                    panel.makeKeyAndOrderFront(nil)
                    panel.orderFrontRegardless()
                    
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        context.allowsImplicitAnimation = true
                        panel.animator().alphaValue = 1.0
                    } completionHandler: {
                        self.isTransitioning = false
                        print("✅ Listen window visible")
                    }
                    
                    self.repositionAllVisiblePanels(animated: true)
                }
            }
        }
    }
    
    func hideChat() {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                guard let chatPanel = self.chatWindow, chatPanel.isVisible else {
                    print("ℹ️ Chat already hidden")
                    return
                }
                
                chatPanel.orderOut(nil)
                self.detachChild(chatPanel)
                chatPanel.alphaValue = 1.0
                
                print("✅ Chat window hidden")
                self.repositionAllVisiblePanels(animated: false)
            }
        }
    }
    
    func hideListen() {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                guard let listenPanel = self.listenWindow, listenPanel.isVisible else {
                    print("ℹ️ Listen already hidden")
                    return
                }
                
                listenPanel.orderOut(nil)
                self.detachChild(listenPanel)
                listenPanel.alphaValue = 1.0
                
                print("✅ Listen window hidden")
                self.repositionAllVisiblePanels()
            }
        }
    }
    
    func hideAll() {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prevent overlapping hide operations
            guard !self.isHiding else {
                print("⏳ Hide skipped - already hiding")
                return
            }
            
            self.isHiding = true
            
            DispatchQueue.main.async {
                // Save visibility state
                self.wasChatVisible = self.chatWindow?.isVisible == true
                self.wasListenVisible = self.listenWindow?.isVisible == true
                
                print("💾 Saved state - Chat: \(self.wasChatVisible), Listen: \(self.wasListenVisible)")
                
                // Hide chat
                if let chatPanel = self.chatWindow, chatPanel.isVisible {
                    self.detachChild(chatPanel)
                    chatPanel.orderOut(nil)
                    chatPanel.alphaValue = 1.0
                }
                
                // Hide listen
                if let listenPanel = self.listenWindow, listenPanel.isVisible {
                    self.detachChild(listenPanel)
                    listenPanel.orderOut(nil)
                    listenPanel.alphaValue = 1.0
                }
                
                // Hide buttons
                if let buttonsPanel = self.buttonsWindow, buttonsPanel.isVisible {
                    buttonsPanel.orderOut(nil)
                    buttonsPanel.alphaValue = 1.0
                }
                
                // Reset flags
                self.isTransitioning = false
                self.isHiding = false
                
                print("✅ All windows hidden")
            }
        }
    }
    
    // MARK: - Panel Coordination
    
    func coordinatePanels() {
        windowQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Always show buttons first
                if self.buttonsWindow?.isVisible != true {
                    self.showButtons()
                }
                
                // Restore chat
                if self.wasChatVisible {
                    if self.chatWindow == nil {
                        self.chatWindow = self.createChatWindow()
                    }
                    
                    if let chatPanel = self.chatWindow {
                        self.positionChatWindow()
                        self.attachChild(chatPanel) {
                            self.positionChatWindow()
                            chatPanel.makeKeyAndOrderFront(nil)
                            chatPanel.orderFrontRegardless()
                            print("✅ Restored chat window")
                        }
                    }
                }
                
                // Restore listen
                if self.wasListenVisible {
                    if self.listenWindow == nil {
                        self.listenWindow = self.createListenWindow()
                    }
                    
                    if let listenPanel = self.listenWindow {
                        self.positionListenWindow()
                        self.attachChild(listenPanel) {
                            self.positionListenWindow()
                            listenPanel.makeKeyAndOrderFront(nil)
                            listenPanel.orderFrontRegardless()
                            print("✅ Restored listen window")
                        }
                    }
                }
            }
        }
    }
    
    private func repositionAllVisiblePanels(animated: Bool = false) {
        if let chatPanel = chatWindow, chatPanel.isVisible {
            positionChatWindow(animated: animated)
        }
        
        if let listenPanel = listenWindow, listenPanel.isVisible {
            positionListenWindow(animated: animated)
        }
    }
    
    // MARK: - Position Management
    
    private func positionButtonsWindow() {
        guard let panel = buttonsWindow else { return }
        
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        let x: CGFloat
        let y: CGFloat
        
        if let lastPos = lastPosition {
            x = lastPos.x
            y = lastPos.y
        } else {
            x = screen.origin.x + (screen.width - buttonsSize.width) / 2
            y = screen.origin.y + screen.height - buttonsSize.height - 20
        }
        
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: buttonsSize)
        panel.setFrame(frame, display: false)
    }
    
    private func positionChatWindow(animated: Bool = false) {
        guard let buttonsPanel = buttonsWindow, let chatPanel = chatWindow else { return }
        let buttonsFrame = buttonsPanel.frame
        let scale = buttonsPanel.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        
        let targetXFloat = buttonsFrame.midX - chatSize.width / 2.0
        let targetYFloat = buttonsFrame.minY - chatSize.height - 8.0
        
        let alignedX = round(targetXFloat * scale) / scale
        let alignedY = round(targetYFloat * scale) / scale
        
        let frame = CGRect(origin: CGPoint(x: alignedX, y: alignedY), size: chatSize)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                chatPanel.animator().setFrame(frame, display: true)
            }
        } else {
            chatPanel.setFrame(frame, display: true)
        }
    }
    
    private func positionListenWindow(animated: Bool = false) {
        guard let buttonsPanel = buttonsWindow, let listenPanel = listenWindow else { return }
        let buttonsFrame = buttonsPanel.frame
        let scale = buttonsPanel.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        
        let isChatVisible = chatWindow?.isVisible == true
        let targetYFloat = buttonsFrame.minY - listenSize.height - 8.0
        let alignedY = round(targetYFloat * scale) / scale
        
        let targetXFloat: CGFloat
        if isChatVisible, let chat = chatWindow {
            targetXFloat = chat.frame.minX - 8.0 - listenSize.width
        } else {
            targetXFloat = buttonsFrame.midX - listenSize.width / 2.0
        }
        let alignedX = round(targetXFloat * scale) / scale
        let frame = CGRect(origin: CGPoint(x: alignedX, y: alignedY), size: listenSize)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                listenPanel.animator().setFrame(frame, display: true)
            }
        } else {
            listenPanel.setFrame(frame, display: true)
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowMoved(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }
    
    @objc private func handleWindowMoved(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if window == buttonsWindow {
            lastPosition = window.frame.origin
        }
    }
    
    // MARK: - Screen Capture Visibility Management
    
    func updateSharingType() {
        let sharingType: NSWindow.SharingType = AppConfig.isVisibleInScreenCapture ? .readOnly : .none
        
        buttonsWindow?.sharingType = sharingType
        chatWindow?.sharingType = sharingType
        listenWindow?.sharingType = sharingType
        
        print("🔄 Updated sharing type for all windows: \(sharingType == .readOnly ? "visible" : "hidden")")
    }
}