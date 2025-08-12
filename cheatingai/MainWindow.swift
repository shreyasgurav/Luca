import SwiftUI
import AppKit

class MainWindow {
    static let shared = MainWindow()
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
            let mainAppView = MainAppView()
            let hostingController = NSHostingController(rootView: mainAppView)
            
            self.window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            
            self.window?.title = "CheatingAI"
            self.window?.contentViewController = hostingController
            self.window?.isReleasedWhenClosed = false
            self.window?.center()
            
            // Set minimum size
            self.window?.minSize = NSSize(width: 400, height: 500)
        }
    }
}
