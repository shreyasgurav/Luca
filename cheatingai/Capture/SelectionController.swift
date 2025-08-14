import AppKit

final class SelectionController: NSObject, SelectionOverlayDelegate {
    private var overlayWindows: [SelectionOverlayWindow] = []

    func beginSelectionFlow() {
        // For MVP, limit to the main screen only to avoid cross-display selections.
        guard let screen = NSScreen.main else { return }
        let overlay = SelectionOverlayWindow(screen: screen)
        overlay.selectionDelegate = self
        overlay.makeKeyAndOrderFront(nil)
        overlay.isMovableByWindowBackground = false
        overlay.isExcludedFromWindowsMenu = true
        overlay.collectionBehavior.insert(.transient)
        overlayWindows = [overlay]
    }

    func selectionOverlayDidFinish(_ overlay: SelectionOverlayWindow, rectInWindow: CGRect) {
        guard let screen = overlay.screen else { 
            ResponseOverlay.shared.show(text: "❌ Error: No screen found")
            return 
        }
        
        print("📸 Starting capture for rect: \(rectInWindow)")
        print("📱 Screen info: \(screen.frame) - scale: \(screen.backingScaleFactor)")
        
        guard let capture = CaptureManager.capture(from: overlay, rectInWindowCoords: rectInWindow, on: screen) else {
            ResponseOverlay.shared.show(text: "❌ Error: Failed to capture screenshot")
            return
        }
        
        overlay.orderOut(nil)
        overlayWindows.removeAll()

        let imageData = capture.jpegData
        print("📤 Uploading image: \(imageData.count) bytes")
        
        // Show loading state immediately
        ResponseOverlay.shared.show(text: "📸 Analyzing your screenshot...")
        
        ClientAPI.shared.uploadAndAnalyze(imageData: imageData, includeOCR: false, sessionId: SessionManager.shared.currentSessionId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let assistantText):
                    print("✅ Received response: \(assistantText.prefix(100))...")
                    ResponseOverlay.shared.show(text: assistantText)
                case .failure(let error):
                    print("❌ API Error: \(error)")
                    ResponseOverlay.shared.show(text: "❌ Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func selectionOverlayDidCancel(_ overlay: SelectionOverlayWindow) {
        overlay.orderOut(nil)
        overlayWindows.removeAll()
    }

    func selectionOverlayDidCopy(_ overlay: SelectionOverlayWindow, rectInWindow: CGRect) {
        guard let screen = overlay.screen else { return }
        guard let capture = CaptureManager.capture(from: overlay, rectInWindowCoords: rectInWindow, on: screen) else { return }
        let image = NSImage(cgImage: capture.cgImage, size: .zero)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        overlay.orderOut(nil)
        overlayWindows.removeAll()
    }
}


