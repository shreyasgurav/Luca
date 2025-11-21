import SwiftUI
import AppKit

/// Simplified ScreenSizeManager for fixed-dimension multi-window architecture
/// No more responsive calculations - just provides basic screen detection
class ScreenSizeManager: ObservableObject {
    static let shared = ScreenSizeManager()
    
    // MARK: - Screen Size Categories (kept for debugging)
    enum ScreenSizeCategory {
        case small      // < 1440px
        case medium     // 1440-1920px
        case large      // 1920-2560px
        case xlarge     // > 2560px
    }
    
    private init() {}
    
    // MARK: - Basic Screen Detection
    
    /// Get current screen size category
    func getScreenSizeCategory() -> ScreenSizeCategory {
        let screenWidth = getCurrentScreenWidth()
        
        switch screenWidth {
        case ..<1440:
            return .small
        case 1440..<1920:
            return .medium
        case 1920..<2560:
            return .large
        default:
            return .xlarge
        }
    }
    
    /// Get current screen width
    func getCurrentScreenWidth() -> CGFloat {
        return NSScreen.main?.visibleFrame.width ?? 1440
    }
    
    /// Get current screen height
    func getCurrentScreenHeight() -> CGFloat {
        return NSScreen.main?.visibleFrame.height ?? 900
    }
    
    // MARK: - Utility Functions
    
    /// Check if screen is small
    func isSmallScreen() -> Bool {
        return getScreenSizeCategory() == .small
    }
    
    /// Check if screen is large
    func isLargeScreen() -> Bool {
        return getScreenSizeCategory() == .large || getScreenSizeCategory() == .xlarge
    }
    
    /// Get screen size description for debugging
    func getScreenSizeDescription() -> String {
        let category = getScreenSizeCategory()
        let width = getCurrentScreenWidth()
        let height = getCurrentScreenHeight()
        
        return "\(category) (\(Int(width))x\(Int(height)))"
    }
    
    // MARK: - Legacy Compatibility (returns fixed values)
    
    /// Legacy method - returns fixed overlay width
    func getResponsiveOverlayWidth() -> CGFloat {
        return 370 // Fixed buttons width
    }
    
    /// Legacy method - returns fixed listen width
    func getResponsiveListenWidth() -> CGFloat {
        return 320 // Fixed listen width
    }
    
    /// Legacy method - returns fixed chat width
    func getResponsiveChatWidth() -> CGFloat {
        return 500 // Fixed chat width
    }
    
    /// Legacy method - returns fixed input width
    func getResponsiveInputWidth() -> CGFloat {
        return 300 // Fixed input width
    }
    
    /// Legacy method - returns fixed spacing
    func getResponsiveSpacing() -> CGFloat {
        return 8 // Fixed spacing
    }
    
    /// Legacy method - returns fixed padding
    func getResponsivePadding() -> CGFloat {
        return 40 // Fixed padding
    }
}

/*
REMOVED FROM ORIGINAL ScreenSizeManager.swift:

1. All responsive calculation logic:
   - scaleFactors dictionary
   - baseOverlayWidth, baseListenWidth, etc.
   - Complex responsive calculations
   - Dynamic scaling based on screen size

2. Freeze mechanism:
   - frozenWidth, frozenHeight
   - freezeOnce() method
   - Oscillation prevention logic

3. All dynamic sizing methods:
   - getResponsiveOverlayWidth() (now returns fixed value)
   - getResponsiveListenWidth() (now returns fixed value)
   - getResponsiveChatWidth() (now returns fixed value)
   - getResponsiveSpacing() (now returns fixed value)
   - getResponsivePadding() (now returns fixed value)

These are now handled by:
- Fixed dimensions in WindowOrchestrator
- No more dynamic calculations needed
- Each window has its own fixed size
- No more resize conflicts or oscillations
*/