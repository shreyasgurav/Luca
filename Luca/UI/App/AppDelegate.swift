import Cocoa
import SwiftUI
import Carbon.HIToolbox
import CoreGraphics
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var selectionController: SelectionController?
    // Command+Return hotkey removed

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set dock visibility based on screen capture setting
        let shouldHideFromDock = !AppConfig.isVisibleInScreenCapture
        NSApp.setActivationPolicy(shouldHideFromDock ? .accessory : .regular)
        
        // Sync auto-launch setting with Login Items
        AppConfig.syncAutoLaunchWithLoginItems()
        
        setupStatusItem()
        setupProductionHotKeys()

        // Pre-warm selection controller
        selectionController = SelectionController()
        
        // Initialize authentication manager immediately so it can drive UI state
        Task { @MainActor in
            _ = AuthenticationManager.shared
            MainWindow.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // NEW: Clean up all hotkeys using the manager
        GlobalHotKeyManager.shared.unregisterAll()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
                    // Use white menu bar logo without text
        if let menuLogo = NSImage(named: "LucaLogoWhite") {
            menuLogo.size = NSSize(width: 18, height: 18)
            button.image = menuLogo
        } else {
            button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Luca")
        }
            // Icon only in the status bar
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            button.target = self
            button.action = #selector(toggleResponseOverlay)
        }

        // Remove menu - clicking the button will directly toggle overlay
        statusItem.menu = nil
    }

    // MARK: - Production Hotkeys (global, works without app activation)
    private func setupProductionHotKeys() {
        // Command+\ → Toggle overlay (main-actor hop)
        _ = GlobalHotKeyManager.shared.registerHotKey(
            keyCode: UInt32(kVK_ANSI_Backslash),
            modifiers: [.command]
        ) { [weak self] in
            Task { @MainActor in
                await self?.toggleResponseOverlaySafely()
            }
        }

        // Command+Return hotkey removed as requested

        // Command+Delete hotkey removed as requested

        // Command+ForwardDelete hotkey removed as requested

        // Command+Option+H → Toggle screen capture visibility
        _ = GlobalHotKeyManager.shared.registerHotKey(
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: [.command, .option]
        ) { [weak self] in
            Task { @MainActor in
                self?.toggleScreenCaptureVisibility()
            }
        }
        
        print("🚀 Production hotkey system initialized (safe mode)")
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            GlobalHotKeyManager.shared.printDiagnostics()
        }
        #endif
    }

    // Command+Return hotkey functionality removed
    
    // Remove old checkAuthAndExecuteAskQuestion (replaced by performAskHotkey)

    // Clear chat hotkey functionality removed

    // Deprecated: replaced by setupProductionHotKeys
    
    private func setupCommandReturnListener() {
        // Listen for Command+Return and Command+Delete anywhere in the app
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 36: // Return key
                    Task { @MainActor in
                        self?.triggerAskQuestion()
                    }
                    return nil
                case 51: // Delete key
                    Task { @MainActor in
                        self?.triggerClearChat()
                    }
                    return nil
                default:
                    break
                }
            }
            return event
        }
        
        // Set up global notification listeners that are always active
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TriggerAskQuestion"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAskQuestionNotification()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TriggerClearChat"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleClearChatNotification()
            }
        }
    }
    
    @MainActor
    private func triggerAskQuestion() {
        // Check if user is authenticated before triggering ask question
        guard AuthenticationManager.shared.isAuthenticated else {
            // If not authenticated, show the main window instead
            MainWindow.shared.show()
            return
        }
        
        // Post a notification that the ask question button should be triggered
        NotificationCenter.default.post(name: NSNotification.Name("TriggerAskQuestion"), object: nil)
    }
    
    @MainActor
    private func triggerClearChat() {
        // Check if user is authenticated before triggering clear chat
        guard AuthenticationManager.shared.isAuthenticated else {
            // If not authenticated, show the main window instead
            MainWindow.shared.show()
            return
        }
        
        // Post a notification that the clear chat button should be triggered
        NotificationCenter.default.post(name: NSNotification.Name("TriggerClearChat"), object: nil)
    }
    
    @MainActor
    private func handleAskQuestionNotification() {
        // Check if user is authenticated before showing overlay
        guard AuthenticationManager.shared.isAuthenticated else {
            // If not authenticated, show the main window instead
            MainWindow.shared.show()
            return
        }
        
        // If panel not shown, show it first
        if ResponseOverlay.shared.panel == nil || !ResponseOverlay.shared.panel!.isVisible {
            ResponseOverlay.shared.show()
            
            // Wait a bit for the panel to be created and visible, then trigger ask question
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.triggerAskQuestionInPanel()
            }
        } else {
            // Panel is already visible, trigger ask question immediately
            triggerAskQuestionInPanel()
        }
    }
    
    private func triggerAskQuestionInPanel() {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.triggerAskQuestionInPanel()
            }
            return
        }
        
        // Check if panel exists and is properly configured
        guard let panel = ResponseOverlay.shared.panel,
              panel.isVisible else {
            print("⚠️ Panel not ready for ask question, retrying in 0.5 seconds...")
            // Retry using the retry mechanism
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.triggerAskQuestionInPanelWithRetry()
            }
            return
        }
        
        // Panel is ready, post notification to execute ask question
        NotificationCenter.default.post(name: NSNotification.Name("ExecuteAskQuestion"), object: nil)
        print("✅ Ask question notification posted successfully")
    }
    
    // Retry mechanism removed with Command+Return hotkey
    
    // Old retry path no longer used (kept for reference)
    private func triggerAskQuestionInPanelWithRetry() { triggerAskQuestionInPanel() }

    // Helper used by toggle hotkey to safely toggle overlay on main actor
    @MainActor
    private func toggleResponseOverlaySafely() async {
        if !AuthenticationManager.shared.isAuthenticated {
            MainWindow.shared.show()
            return
        }

        // Check if all permissions are granted before showing overlay
        if !areAllPermissionsGranted() {
            print("⚠️ Cannot show overlay - permissions not granted")
            return
        }

        if let panel = ResponseOverlay.shared.panel {
            if panel.isVisible {
                ResponseOverlay.shared.hide()
            } else {
                ResponseOverlay.shared.show()
            }
        } else {
            ResponseOverlay.shared.show()
        }
    }
    
    // Helper to check if all permissions are granted
    private func areAllPermissionsGranted() -> Bool {
        // Check screen recording permission
        let screenRecordingGranted = CGPreflightScreenCaptureAccess()
        
        // Check microphone permission
        let microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        // Check speech recognition permission
        let speechRecognitionGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        
        return screenRecordingGranted && microphoneGranted && speechRecognitionGranted
    }
    
    private func handleClearChatNotification() {
        // If panel not shown, nothing to clear
        guard ResponseOverlay.shared.panel != nil && ResponseOverlay.shared.panel!.isVisible else {
            return
        }
        
        // Post notification to execute clear chat
        NotificationCenter.default.post(name: NSNotification.Name("ExecuteClearChat"), object: nil)
    }
    
    private func setupToggleOverlayHotKey() {
        // This is now redundant since globalHotKey handles Command+\
        // Keeping for backward compatibility but not registering
    }
    
    // Command+Return hotkey removed as requested

    @MainActor
    @objc private func toggleSelection() {
        // Use async check to avoid blocking
        checkAuthenticationAsync { isAuthenticated in
            DispatchQueue.main.async {
                if isAuthenticated {
                    // Directly show the response overlay
                    ResponseOverlay.shared.show(text: "")
                } else {
                    // If not authenticated, show the main window instead
                    MainWindow.shared.show()
                }
            }
        }
    }
    
    @objc private func toggleResponseOverlay() {
        // Use async check to avoid blocking - FIXED
        checkAuthenticationAsync { isAuthenticated in
            DispatchQueue.main.async {
                if !isAuthenticated {
                    // If not authenticated, show the main window instead
                    MainWindow.shared.show()
                    return
                }
                // Ensure permissions are granted before toggling
                let screenOK = CGPreflightScreenCaptureAccess()
                let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
                guard screenOK && micOK && speechOK else {
                    MainWindow.shared.show()
                    return
                }

                // Toggle the floating modal visibility
                if let panel = ResponseOverlay.shared.panel {
                    if panel.isVisible {
                        ResponseOverlay.shared.hide()
                    } else {
                        ResponseOverlay.shared.show()
                    }
                } else {
                    // If panel doesn't exist, create and show it
                    ResponseOverlay.shared.show()
                }
            }
        }
    }
    


    @objc private func showSignIn() {
        MainWindow.shared.show()
    }
    
    @objc private func signOut() {
        Task { @MainActor in
            AuthenticationManager.shared.signOut()
        }
    }
    
    @objc private func showMemoryManager() {
        MemoryManagementWindow.shared.show()
    }
    
    @objc private func showVectorMemory() {
        VectorMemoryWindow.shared.show()
    }
    
    @objc private func showDashboard() {
        MainWindow.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
    
    // HELPER: Async authentication check to prevent main thread blocking
    private func checkAuthenticationAsync(completion: @escaping (Bool) -> Void) {
        // Use main queue for authentication check to avoid actor isolation issues
        DispatchQueue.main.async {
            let isAuthenticated = AuthenticationManager.shared.isAuthenticated
            completion(isAuthenticated)
        }
    }
    
    // MARK: - Screen Capture Visibility Toggle
    
    @MainActor
    private func toggleScreenCaptureVisibility() {
        let newValue = !AppConfig.isVisibleInScreenCapture
        AppConfig.isVisibleInScreenCapture = newValue
        
        // Update existing windows
        ResponseOverlay.shared.panel?.sharingType = newValue ? .readOnly : .none
        MainWindow.shared.updateSharingType()
        // Update multi-window overlay system
        WindowOrchestrator.shared.updateSharingType()
        // Update tooltip windows
        TooltipWindowManager.shared.updateSharingType()
        
        // Show notification
        let status = newValue ? "visible" : "hidden"
        ResponseOverlay.shared.show(text: "📹 Luca is now \(status) in screen captures")
        
        print("🔄 Screen capture visibility toggled: \(status)")
    }
}


