import SwiftUI

/// Centralized design system for consistent visual styling across all overlay components
/// Provides standardized corner radius, opacity, colors, and spacing values
struct DesignSystem {
    
    // MARK: - Corner Radius Standards
    struct CornerRadius {
        static let small: CGFloat = 8      // Small buttons, tooltips
        static let medium: CGFloat = 12    // Input fields, small panels
        static let large: CGFloat = 16     // Chat panels, listen panel
        static let xlarge: CGFloat = 20    // Main overlay background
        static let pill: CGFloat = 25      // Overlay buttons container
    }
    
    // MARK: - Background Opacity Standards
    struct BackgroundOpacity {
        static let subtle: Double = 0.05   // Very light backgrounds
        static let light: Double = 0.1     // Button hover states
        static let medium: Double = 0.15   // Button backgrounds
        static let strong: Double = 0.2    // Panel borders
        static let heavy: Double = 0.3     // Separators
        static let panel: Double = 0.6     // Chat panel background
        static let overlay: Double = 0.75  // Main overlay background
        static let dark: Double = 0.85     // Listen panel background
        static let tooltip: Double = 0.9   // Tooltip backgrounds
    }
    
    // MARK: - Text Opacity Standards
    struct TextOpacity {
        static let disabled: Double = 0.4  // Disabled text
        static let secondary: Double = 0.5 // Secondary text
        static let muted: Double = 0.6     // Muted text
        static let regular: Double = 0.7   // Regular text
        static let prominent: Double = 0.8 // Prominent text
        static let primary: Double = 0.9   // Primary text
        static let active: Double = 1.0    // Active text
    }
    
    // MARK: - Shadow Standards
    struct Shadow {
        static let light = ShadowConfig(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        static let medium = ShadowConfig(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        static let heavy = ShadowConfig(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        static let strong = ShadowConfig(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        
        struct ShadowConfig {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
    
    // MARK: - Color Standards
    struct Colors {
        // Background colors - Liquid Glass Effect
        static let background = Color.clear // Will use gradient + blur
        static let panelBackground = Color.clear // Will use gradient + blur
        static let listenPanelBackground = Color.clear // Will use gradient + blur
        
        // Liquid glass gradients
        static let liquidGlassLight = LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0.25),
                Color.white.opacity(0.1),
                Color.white.opacity(0.15)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let liquidGlassDark = LinearGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(0.3),
                Color.black.opacity(0.15),
                Color.black.opacity(0.25)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Accent colors
        static let primary = Color.blue
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        
        // Interactive colors
        static let hoverBackground = Color.black.opacity(0.08)
        static let activeBackground = Color.black.opacity(0.12)
        static let borderColor = Color.black.opacity(0.25)
        
        // Text colors - Dark text on white background
        static let primaryText = Color.black.opacity(0.9)
        static let secondaryText = Color.black.opacity(0.7)
        static let mutedText = Color.black.opacity(0.5)
        static let disabledText = Color.black.opacity(0.3)
    }
    
    // MARK: - Spacing Standards
    struct Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
    }
    
    // MARK: - Animation Standards
    struct Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let medium = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
    }
}

// MARK: - Convenience Extensions

extension View {
    /// Apply standard corner radius based on component type
    func standardCornerRadius(_ type: CornerRadiusType) -> some View {
        let radius: CGFloat
        switch type {
        case .small: radius = DesignSystem.CornerRadius.small
        case .medium: radius = DesignSystem.CornerRadius.medium
        case .large: radius = DesignSystem.CornerRadius.large
        case .xlarge: radius = DesignSystem.CornerRadius.xlarge
        case .pill: radius = DesignSystem.CornerRadius.pill
        }
        return self.clipShape(RoundedRectangle(cornerRadius: radius))
    }
    
    /// Apply standard shadow based on intensity
    func standardShadow(_ intensity: ShadowIntensity) -> some View {
        let shadow: DesignSystem.Shadow.ShadowConfig
        switch intensity {
        case .light: shadow = DesignSystem.Shadow.light
        case .medium: shadow = DesignSystem.Shadow.medium
        case .heavy: shadow = DesignSystem.Shadow.heavy
        case .strong: shadow = DesignSystem.Shadow.strong
        }
        return self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

enum CornerRadiusType {
    case small, medium, large, xlarge, pill
}

enum ShadowIntensity {
    case light, medium, heavy, strong
}
