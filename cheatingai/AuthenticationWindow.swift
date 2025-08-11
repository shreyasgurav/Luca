import SwiftUI
import AppKit

class AuthenticationWindow {
    static let shared = AuthenticationWindow()
    private var window: NSWindow?
    
    private init() {}
    
    func show() {
        if window == nil {
            createWindow()
        }
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    private func createWindow() {
        DispatchQueue.main.async {
            let signInView = SignInView()
            let hostingController = NSHostingController(rootView: signInView)
            
            self.window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            
            self.window?.title = "Sign In - CheatingAI"
            self.window?.contentViewController = hostingController
            self.window?.isReleasedWhenClosed = false
            self.window?.center()
            
            // Close window when authentication succeeds
            let authManager = AuthenticationManager.shared
            let cancellable = authManager.$isAuthenticated
                .sink { [weak self] isAuthenticated in
                    if isAuthenticated {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.hide()
                        }
                    }
                }
            
            // Store the cancellable to prevent it from being deallocated
            if let window = self.window {
                objc_setAssociatedObject(window, "cancellable", cancellable, .OBJC_ASSOCIATION_RETAIN)
            }
        }
    }
}
