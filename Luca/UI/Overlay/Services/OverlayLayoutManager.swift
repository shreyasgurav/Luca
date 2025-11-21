import SwiftUI
import AppKit

/// Simplified OverlayLayoutManager for fixed-dimension multi-window architecture
/// No more dynamic calculations - just provides fixed dimensions for each window
class OverlayLayoutManager: ObservableObject {
    static let shared = OverlayLayoutManager()
    
    // MARK: - Fixed Dimensions (No more responsive calculations)
    
    /// Fixed dimensions for each window type
    let buttonsSize = CGSize(width: 370, height: 40)
    let chatSize = CGSize(width: 500, height: 300)
    let listenSize = CGSize(width: 320, height: 300)
    
    /// Fixed spacing between windows
    let windowSpacing: CGFloat = 8
    
    private init() {}
    
    // MARK: - Legacy Compatibility (for existing code)
    
    /// Legacy method - returns fixed buttons width
    func getOverlayButtonsWidth() -> CGFloat {
        return buttonsSize.width
    }
    
    /// Legacy method - returns fixed listen panel width
    func getListenPanelWidth() -> CGFloat {
        return listenSize.width
    }
    
    /// Legacy method - returns fixed chat view min width
    var chatViewMinWidthValue: CGFloat {
        return chatSize.width
    }
    
    /// Legacy method - returns fixed chat view max width
    var chatViewMaxWidthValue: CGFloat {
        return chatSize.width // Same as min since it's fixed
    }
    
    /// Legacy method - returns fixed panel spacing
    func getPanelSpacing() -> CGFloat {
        return windowSpacing
    }
    
    /// Legacy method - returns fixed panel padding
    func getPanelPadding() -> CGFloat {
        return 40 // Fixed padding
    }
    
    /// Legacy method - returns fixed input width
    func getResponsiveInputWidth() -> CGFloat {
        return 300 // Fixed input width
    }
    
    // MARK: - Simplified Panel Width Calculation
    
    /// Calculate total panel width (legacy compatibility)
    func panelWidth(isListening: Bool, hasChat: Bool) -> CGFloat {
        if isListening && hasChat {
            return chatSize.width + listenSize.width + windowSpacing + 40
        } else if hasChat {
            return chatSize.width + 40
        } else if isListening {
            return listenSize.width + 40
        } else {
            return buttonsSize.width
        }
    }
    
    /// Get chat view width constraints (legacy compatibility)
    func chatViewWidthConstraints(isListening: Bool) -> (minWidth: CGFloat, maxWidth: CGFloat) {
        return (minWidth: chatSize.width, maxWidth: chatSize.width)
    }
    
    // MARK: - Debug Information
    
    /// Get layout description for debugging
    func getLayoutDescription() -> String {
        return "Fixed Layout - Buttons: \(Int(buttonsSize.width))x\(Int(buttonsSize.height)), Chat: \(Int(chatSize.width))x\(Int(chatSize.height)), Listen: \(Int(listenSize.width))x\(Int(listenSize.height))"
    }
}

/*
REMOVED FROM ORIGINAL OverlayLayoutManager.swift:

1. All responsive calculation logic:
   - screenSizeManager dependency
   - baseOverlayButtonsWidth, baseListenPanelWidth, etc.
   - overlayButtonsWidthValue, listenPanelWidthValue, etc.
   - Complex responsive calculations

2. All dynamic sizing methods:
   - getResponsiveOverlayWidth()
   - getResponsiveListenWidth()
   - getResponsiveChatWidth()
   - getResponsiveSpacing()
   - getResponsivePadding()
   - getResponsiveInputWidth()

3. All screen size dependencies:
   - ScreenSizeManager integration
   - Responsive scale factors
   - Screen size categories

These are now handled by:
- Fixed dimensions in WindowOrchestrator
- No more dynamic calculations needed
- Each window has its own fixed size
- Positioning handled by WindowOrchestrator
*/