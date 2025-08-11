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
    private var toggleOverlayHotKey: GlobalHotKey?

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
        setupToggleOverlayHotKey()

        // Pre-warm selection controller
        selectionController = SelectionController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKey?.unregister()
        toggleOverlayHotKey?.unregister()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "CheatingAI")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(toggleSelection)
        }

        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open AI Assistant\t⌘\\", action: #selector(toggleSelection), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Response Overlay\t⌘/", action: #selector(toggleResponseOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Memory Manager", action: #selector(showMemoryManager), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Vector Memory", action: #selector(showVectorMemory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Sign In", action: #selector(showSignIn), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CheatingAI", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupGlobalHotKey() {
        globalHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_Backslash), modifiers: [.command]) { [weak self] in
            self?.toggleSelection()
        }
        globalHotKey?.register()
    }
    
    private func setupToggleOverlayHotKey() {
        toggleOverlayHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_Slash), modifiers: [.command]) { [weak self] in
            self?.toggleResponseOverlay()
        }
        toggleOverlayHotKey?.register()
    }

    @objc private func toggleSelection() {
        // Directly show the response overlay
        ResponseOverlay.shared.show(text: "")
    }
    
    @objc private func toggleResponseOverlay() {
        if let panel = ResponseOverlay.shared.panel {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
                panel.center()
            }
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
        AuthenticationWindow.shared.show()
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}


