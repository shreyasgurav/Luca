import Cocoa
import SwiftUI
import Carbon.HIToolbox
import FirebaseCore
import GoogleSignIn

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var selectionController: SelectionController?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        setupGlobalHotKey()
        setupCommandReturnListener()

        // Pre-warm selection controller
        selectionController = SelectionController()
        
        // Start location updates (with user consent)
        LocationManager.shared.start()
        
        // Migrate existing transcripts to user's Documents folder
        Task {
            await SessionTranscriptStore.shared.migrateExistingTranscripts()
        }

        // Let AuthenticationManager handle all UI state changes
        // It will automatically show appropriate windows based on auth state
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKey?.unregister()
        
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

    private func setupGlobalHotKey() {
        globalHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_Backslash), modifiers: [.command]) { [weak self] in
            self?.toggleResponseOverlay()
        }
        globalHotKey?.register()
    }
    
    private func setupCommandReturnListener() {
        // Listen for Command+Return and Command+Delete anywhere in the app
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 36: // Return key
                    self?.triggerAskQuestion()
                    return nil
                case 51: // Delete key
                    self?.triggerClearChat()
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
            self?.handleAskQuestionNotification()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TriggerClearChat"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleClearChatNotification()
        }
    }
    
    private func triggerAskQuestion() {
        // Post a notification that the ask question button should be triggered
        NotificationCenter.default.post(name: NSNotification.Name("TriggerAskQuestion"), object: nil)
    }
    
    private func triggerClearChat() {
        // Post a notification that the clear chat button should be triggered
        NotificationCenter.default.post(name: NSNotification.Name("TriggerClearChat"), object: nil)
    }
    
    private func handleAskQuestionNotification() {
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
        // Find the CompactView and trigger ask question
        if let panel = ResponseOverlay.shared.panel,
           let hostingController = panel.contentViewController as? NSHostingController<ResponsePanel> {
            
            // Access the CompactView through the hosting controller
            // We need to find a way to trigger the ask question functionality
            // For now, let's just ensure the panel is focused
            panel.makeKey()
            
            // Post another notification that the view should listen for
            NotificationCenter.default.post(name: NSNotification.Name("ExecuteAskQuestion"), object: nil)
        }
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


