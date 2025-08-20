import SwiftUI

final class SessionDetailWindow {
    private var window: NSWindow?
    private let session: SessionTranscriptStore.TranscriptSession
    
    init(session: SessionTranscriptStore.TranscriptSession) {
        self.session = session
    }
    
    func show() {
        let view = SessionDetailView(session: session)
        let hosting = NSHostingController(rootView: view)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window?.title = "Session Details"
        window?.contentViewController = hosting
        window?.isReleasedWhenClosed = true
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}




