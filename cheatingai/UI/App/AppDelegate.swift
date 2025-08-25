import Cocoa
import SwiftUI
import Carbon.HIToolbox
import FirebaseCore
import GoogleSignIn

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var selectionController: SelectionController?
    // REMOVED: private var globalHotKey: GlobalHotKey? (old single hotkey system)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app to accessory mode to prevent activation from floating overlay
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Register for URL events (required for Google Sign-In redirect)
        let appleEventManager = NSAppleEventManager.shared()
        appleEventManager.setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // Restore previous Google Sign-In session
        AuthenticationManager.shared.restorePreviousSignIn()
        
        setupStatusItem()
        setupProductionHotKeys() // NEW: Updated hotkey system
        // REMOVED: setupCommandReturnListener() (old local event monitor)

        // Pre-warm selection controller
        selectionController = SelectionController()
        
        // Start location updates (with user consent)
        LocationManager.shared.start()
        
        // Migrate existing transcripts to user's Documents folder
        Task {
            await SessionTranscriptStore.shared.migrateExistingTranscripts()
            
            // Test write access to help debug transcript saving
            let writeAccess = SessionTranscriptStore.shared.testWriteAccess()
            print("📁 DEBUG: Write access test result: \(writeAccess ? "SUCCESS" : "FAILED")")
            print("📁 DEBUG: Current save location: \(SessionTranscriptStore.shared.getCurrentSaveLocation())")
            
            // Force test user's Documents folder
            let forceResult = SessionTranscriptStore.shared.forceUseUserDocuments()
            print("📁 DEBUG: Force user Documents test: \(forceResult)")
            
            // Check app permissions
            let permissions = SessionTranscriptStore.shared.checkAppPermissions()
            print("📁 DEBUG: App permissions:\n\(permissions)")
            
            // Test real user directory access methods
            let realDirTest = SessionTranscriptStore.shared.testRealUserDirectoryAccess()
            print("📁 DEBUG: Real directory access test:\n\(realDirTest)")
        }

        // Let AuthenticationManager handle all UI state changes
        // It will automatically show appropriate windows based on auth state
    }

    func applicationWillTerminate(_ notification: Notification) {
        // NEW: Clean up all hotkeys using the manager
        GlobalHotKeyManager.shared.unregisterAll()
        
        // Force cleanup audio capture and screen recording
        AudioCaptureManager.shared.forceCleanup()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use Nova logo instead of system icon
            if let novaLogo = NSImage(named: "NovaLogo") {
                novaLogo.size = NSSize(width: 18, height: 18)
                button.image = novaLogo
            } else {
                button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Nova")
            }
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(toggleSelection)
        }

        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Nova Assistant\t⌘\\", action: #selector(toggleSelection), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Main Window", action: #selector(showSignIn), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Nova", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // NEW: Production hotkey setup using the enhanced system
    private func setupProductionHotKeys() {
        // Command+\ - Toggle overlay (existing functionality)
        GlobalHotKeyManager.shared.registerHotKey(
            keyCode: UInt32(kVK_ANSI_Backslash),
            modifiers: [.command]
        ) { [weak self] in
            print("🔄 Command+\\ detected - toggling overlay")
            self?.toggleResponseOverlay()
        }
        
        // Command+Return - Ask question (NEW)
        GlobalHotKeyManager.shared.registerHotKey(
            keyCode: UInt32(kVK_Return),
            modifiers: [.command]
        ) { [weak self] in
            print("🔥 Command+Return detected - triggering ask question")
            self?.handleAskQuestionHotkey()
        }
        
        // Command+Delete - Clear chat (NEW)
        GlobalHotKeyManager.shared.registerHotKey(
            keyCode: UInt32(kVK_Delete),
            modifiers: [.command]
        ) { [weak self] in
            print("🗑️ Command+Delete detected - clearing chat")
            self?.handleClearChatHotkey()
        }
        
        print("🚀 Production hotkey system initialized")
        
        // Print diagnostics in debug builds
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            GlobalHotKeyManager.shared.printDiagnostics()
        }
        #endif
    }
    
    // NEW: Handle Command+Return hotkey
    private func handleAskQuestionHotkey() {
        DispatchQueue.main.async { [weak self] in
            // If panel is not visible, show it first
            if ResponseOverlay.shared.panel == nil || !ResponseOverlay.shared.panel!.isVisible {
                print("   Panel not visible, showing first...")
                ResponseOverlay.shared.show()
                
                // Wait for panel to be created and visible
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.triggerAskQuestionInPanel()
                }
            } else {
                print("   Panel already visible, triggering immediately...")
                self?.triggerAskQuestionInPanel()
            }
        }
    }
    
    // NEW: Handle Command+Delete hotkey
    private func handleClearChatHotkey() {
        DispatchQueue.main.async {
            // Only proceed if panel is visible
            guard let panel = ResponseOverlay.shared.panel, panel.isVisible else {
                print("   Panel not visible, ignoring clear chat")
                return
            }
            
            print("   Posting clear chat notification...")
            NotificationCenter.default.post(name: NSNotification.Name("ExecuteClearChat"), object: nil)
        }
    }
    
    // NEW: Helper method to trigger ask question in panel
    private func triggerAskQuestionInPanel() {
        if let panel = ResponseOverlay.shared.panel {
            panel.orderFrontRegardless()
            
            print("   Posting ask question notification...")
            NotificationCenter.default.post(name: NSNotification.Name("ExecuteAskQuestion"), object: nil)
        }
    }

    // REMOVED: Old setupGlobalHotKey() method
    // REMOVED: Old setupCommandReturnListener() method
    // REMOVED: Old triggerAskQuestion() and triggerClearChat() methods
    // REMOVED: Old handleAskQuestionNotification() and handleClearChatNotification() methods

    @objc private func toggleSelection() {
        // Directly show the response overlay
        ResponseOverlay.shared.show(text: "")
    }
    
    @objc private func toggleResponseOverlay() {
        // Toggle the floating modal visibility
        if let panel = ResponseOverlay.shared.panel {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
                panel.center()
            }
        } else {
            // If panel doesn't exist, create and show it
            ResponseOverlay.shared.show()
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor?, replyEvent: NSAppleEventDescriptor?) {
        if let urlString = event?.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlString) {
            // Let Google Sign-In SDK handle the URL
            GIDSignIn.sharedInstance.handle(url)
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
}