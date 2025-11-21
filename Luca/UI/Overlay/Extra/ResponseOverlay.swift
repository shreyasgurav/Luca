import AppKit
import SwiftUI
import FirebaseAuth
import AVFoundation
import Speech

/// Simplified ResponseOverlay that delegates to WindowOrchestrator
/// No more single window resizing - uses multi-window architecture
final class ResponseOverlay: NSObject {
    static let shared = ResponseOverlay()
    
    // Legacy property for compatibility - now uses shared conversation store
    var conversationStore: ConversationStore {
        return WindowOrchestrator.shared.conversationStore
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Interface (unchanged for compatibility)
    
    func show(text: String = "") {
        DispatchQueue.main.async {
            // Authentication check
            if Auth.auth().currentUser == nil {
                MainWindow.shared.show()
                return
            }
            // Permissions gate
            if !self.areAllPermissionsGranted() {
                MainWindow.shared.show()
                return
            }
            
            // Show buttons window (always first)
            WindowOrchestrator.shared.showButtons()
            
            // If text provided, show chat with that text
            if !text.isEmpty {
                WindowOrchestrator.shared.showChat(with: text)
            }
            
            // Coordinate all panels to work together
            WindowOrchestrator.shared.coordinatePanels()
            
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func showExpandedChat() {
        DispatchQueue.main.async {
            // Authentication check
            if Auth.auth().currentUser == nil {
                MainWindow.shared.show()
                return
            }
            // Permissions gate
            if !self.areAllPermissionsGranted() {
                MainWindow.shared.show()
                return
            }
            
            // Show buttons and chat windows
            WindowOrchestrator.shared.showButtons()
            WindowOrchestrator.shared.showChat(expanded: true)
            
            // Coordinate all panels to work together
            WindowOrchestrator.shared.coordinatePanels()
            
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func hide() {
        DispatchQueue.main.async {
            WindowOrchestrator.shared.hideAll()
        }
    }
    
    func savePanelOrigin() {
        // No-op: WindowOrchestrator handles position tracking
    }
}

// MARK: - Legacy Compatibility (for existing code that might reference these)

extension ResponseOverlay {
    /// Legacy property - no longer used in multi-window architecture
    var panel: FocusablePanel? {
        return WindowOrchestrator.shared.buttonsWindow
    }
    
    /// Legacy methods - no longer needed with fixed-size windows
    static func isAdjustingFrameGloballyFlag() -> Bool { return false }
    static func setAdjustingFrameGlobally(_ value: Bool) { }
    static func logFrame(_ source: String, action: String, old: CGRect, new: CGRect) { }
}

// MARK: - Permissions helper
extension ResponseOverlay {
    fileprivate func areAllPermissionsGranted() -> Bool {
        let screenCapture = CGPreflightScreenCaptureAccess()
        let micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        return screenCapture && micAuthorized && speechAuthorized
    }
}

// MARK: - Legacy Access Methods

extension ResponseOverlay {
    /// Get the buttons window for legacy compatibility
    private var buttonsPanel: FocusablePanel? {
        // Access through WindowOrchestrator's internal property
        return WindowOrchestrator.shared.buttonsWindow
    }
}

// MARK: - Remove Old ResponsePanel (no longer needed)

// ResponsePanel and all its complex logic is removed
// Each panel now has its own dedicated view file:
// - ButtonsPanelView.swift
// - ChatPanelView.swift  
// - ListenPanelView.swift