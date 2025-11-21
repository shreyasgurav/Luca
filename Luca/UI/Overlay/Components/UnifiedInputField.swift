import SwiftUI

/// Unified input field component that provides consistent behavior across all overlay components
/// Standardizes placeholders, focus management, keyboard shortcuts, and visual styling
struct UnifiedInputField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void
    let style: InputStyle
    let isLoading: Bool
    
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    // REMOVED suggestions for performance
    
    enum InputStyle {
        case compact    // OverlayButtons style - minimal height
        case inline     // InlineInputView style - medium height
        case full       // FullChatView style - full height
    }
    
    // Responsive layout
    @StateObject private var layoutManager = OverlayLayoutManager.shared
    
    var body: some View {
        HStack(spacing: getSpacing()) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: getFontSize(), weight: .regular))
                .foregroundColor(.white)
                .accentColor(.white)
                .padding(.horizontal, getHorizontalPadding())
                .frame(width: getWidth(), height: getHeight())
                .background(
                    RoundedRectangle(cornerRadius: getCornerRadius())
                        .fill(getBackgroundColor())
                        .overlay(
                            RoundedRectangle(cornerRadius: getCornerRadius())
                                .stroke(getBorderColor(), lineWidth: getBorderWidth())
                        )
                )
                .placeholder(when: text.isEmpty) {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: getFontSize(), weight: .regular))
                        .padding(.horizontal, getHorizontalPadding())
                }
                .focused($isFocused)
                .onSubmit {
                    handleSubmit()
                }
                .disabled(isLoading)
            
            // Send button for inline and full styles
            if style != .compact {
                sendButton
            }
        }
        // REMOVED suggestions overlay for performance
        .onAppear {
            setupKeyboardShortcuts()
        }
    }
    
    // MARK: - Style-based Configuration
    
    private func getWidth() -> CGFloat {
        switch style {
        case .compact:
            return layoutManager.getOverlayButtonsWidth() * 0.6 // 60% of overlay width
        case .inline:
            return layoutManager.getResponsiveInputWidth()
        case .full:
            return layoutManager.getResponsiveInputWidth()
        }
    }
    
    private func getHeight() -> CGFloat {
        switch style {
        case .compact:
            return 24
        case .inline:
            return 28
        case .full:
            return 32
        }
    }
    
    private func getFontSize() -> CGFloat {
        switch style {
        case .compact:
            return 12
        case .inline:
            return 12
        case .full:
            return 14
        }
    }
    
    private func getSpacing() -> CGFloat {
        switch style {
        case .compact:
            return 6
        case .inline:
            return 8
        case .full:
            return 12
        }
    }
    
    private func getHorizontalPadding() -> CGFloat {
        switch style {
        case .compact:
            return 8
        case .inline:
            return 10
        case .full:
            return 12
        }
    }
    
    private func getCornerRadius() -> CGFloat {
        switch style {
        case .compact:
            return 12
        case .inline:
            return 14
        case .full:
            return 16
        }
    }
    
    private func getBackgroundColor() -> Color {
        switch style {
        case .compact:
            return Color.white.opacity(0.1)
        case .inline:
            return Color.black.opacity(0.4)
        case .full:
            return Color.black.opacity(0.6)
        }
    }
    
    private func getBorderColor() -> Color {
        if isFocused {
            return Color.blue.opacity(0.6)
        } else {
            return Color.white.opacity(0.2)
        }
    }
    
    private func getBorderWidth() -> CGFloat {
        return isFocused ? 1.5 : 1.0
    }
    
    // MARK: - Send Button
    
    @ViewBuilder
    private var sendButton: some View {
        Button(action: handleSubmit) {
            Image(systemName: isLoading ? "hourglass" : "arrow.up")
                .font(.system(size: getFontSize(), weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(getSendButtonColor()))
        }
        .buttonStyle(.plain)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
    }
    
    private func getSendButtonColor() -> Color {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading {
            return Color.white.opacity(0.2)
        } else {
            return Color.blue.opacity(0.8)
        }
    }
    
    // MARK: - Actions
    
    private func handleSubmit() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty && !isLoading else { return }
        onSubmit()
    }
    
    private func setupKeyboardShortcuts() {
        // Keyboard shortcuts are handled by the parent components
        // This ensures consistent behavior across all input fields
    }
    
    // REMOVED suggestions methods for performance
}

