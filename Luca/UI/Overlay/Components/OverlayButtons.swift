import SwiftUI
import AppKit

// MARK: - OverlayButtons (Siri-like input design)
struct OverlayButtons: View {
    let onListen: () -> Void
    let onAskQuestion: () -> Void
    let onHide: () -> Void
    let onSettings: () -> Void
    let onOpenMainWindow: () -> Void
    @Binding var listenMode: ListenMode
    @Binding var inputText: String
    @State private var listenHover: Bool = false
    @State private var logoHover: Bool = false
    @State private var hideHover: Bool = false
    @FocusState private var isInputFocused: Bool
    @State private var isDragging: Bool = false
    @State private var dragStartLocation: CGPoint = .zero
    
    // Responsive layout
    @StateObject private var layoutManager = OverlayLayoutManager.shared
    
    var body: some View {
        HStack(spacing: 6) {
            // Left: Luca logo
            lucaLogo
            
            // Center: Input field with placeholder
            ZStack(alignment: .leading) {
                    if inputText.isEmpty {
                        Text("Ask about screen...")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(.leading, 0)
                            .animation(DesignSystem.Animation.fast, value: inputText.isEmpty)
                    }
                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .accentColor(DesignSystem.Colors.primary)
                    .focused($isInputFocused)
                    .disabled(OverlayStateManager.shared.isInputFieldDisabled)
                    .opacity(OverlayStateManager.shared.isInputFieldDisabled ? 0.6 : 1.0)
                    .onSubmit {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !OverlayStateManager.shared.isInputFieldDisabled {
                            onAskQuestion()
                        }
                    }
            }
            .scaleEffect(isInputFocused ? 1.02 : 1.0)
            .animation(DesignSystem.Animation.spring, value: isInputFocused)
            
            // Right: Listen controls and hide button
            listenControls
            hideButton
        }
        .frame(width: layoutManager.getOverlayButtonsWidth()) // Responsive width
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.pill)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    // Draw border inside bounds to avoid clipping on left/right
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.pill)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartLocation = value.startLocation
                        NSCursor.closedHand.set()
                    }
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isDragging = false
                        NSCursor.arrow.set()
                    }
                }
        )
        .onHover { hovering in
            if hovering && !isDragging {
                NSCursor.openHand.set()
            } else if !hovering {
                NSCursor.arrow.set()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var lucaLogo: some View {
        Button(action: {
            if !isDragging {
                MainWindow.shared.focusExistingSpace()
            }
        }) {
            // Priority: LucaLogoWhite -> NewLucaLogo -> LucaLogoBlack -> External path -> fallback
            if let _ = NSImage(named: "LucaLogoWhite") {
                Image("LucaLogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(0.95)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(logoHover ? Color.white.opacity(0.10) : Color.clear)
                    )
                    .animation(DesignSystem.Animation.medium, value: logoHover)
            } else if let _ = NSImage(named: "NewLucaLogo") {
                Image("NewLucaLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(0.95)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(logoHover ? Color.white.opacity(0.10) : Color.clear)
                    )
                    .animation(DesignSystem.Animation.medium, value: logoHover)
            } else if let _ = NSImage(named: "LucaLogoBlack") {
                Image("LucaLogoBlack")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(0.95)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(logoHover ? Color.white.opacity(0.10) : Color.clear)
                    )
                    .animation(DesignSystem.Animation.medium, value: logoHover)
            } else if let image = NSImage(contentsOfFile: "/Users/shreyasgurav/Desktop/Luca/assets/Luca Logo NoBG Black.png") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(0.95)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(logoHover ? Color.white.opacity(0.10) : Color.clear)
                    )
                    .animation(DesignSystem.Animation.medium, value: logoHover)
            } else {
                Image("LucaLogoBlack")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(0.95)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(logoHover ? Color.white.opacity(0.10) : Color.clear)
                    )
                    .animation(DesignSystem.Animation.medium, value: logoHover)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: -4)
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.fast) {
                logoHover = hovering
            }
            
            // Show/hide tooltip using separate window
            if hovering {
                // Get button position in screen coordinates
                DispatchQueue.main.async {
                    // Find the actual overlay window (buttons window)
                    if let overlayWindow = WindowOrchestrator.shared.buttonsWindow {
                        // Calculate logo position - it's the leftmost element
                        let logoX: CGFloat = 10.0 // Logo is 10px from left edge
                        let logoY: CGFloat = 18.0 // Center vertically in 36px height overlay
                        let buttonFrame = CGRect(x: logoX, y: logoY, width: 32.0, height: 26.0)
                        let screenPosition = overlayWindow.convertToScreen(buttonFrame).origin
                        TooltipWindowManager.shared.showTooltip(text: "Dashboard", at: screenPosition, parentWindow: overlayWindow, isLeftSide: true)
                    }
                }
            } else {
                // Small delay to ensure hover state is properly detected
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    TooltipWindowManager.shared.hideTooltip()
                }
            }
        }
        .accessibilityLabel("Open main window")
    }
    
    
    private var listenControls: some View {
        // Dimensions
        let itemSize: CGFloat = 26 // Match hide button visual size
        let spacing: CGFloat = 0
        let collapsedWidth: CGFloat = itemSize
        let expandedWidth: CGFloat = itemSize * 2 + spacing

        return ZStack(alignment: .trailing) {
            // Background: match hide button when inactive, expand capsule when active
            if listenMode == .active {
                Capsule()
                    .fill(DesignSystem.Colors.error.opacity(0.25))
                    .frame(width: expandedWidth, height: itemSize)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: listenMode)
                    .scaleEffect(1.0, anchor: .trailing) // no hover scale when active
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: collapsedWidth, height: itemSize)
                    .scaleEffect(listenHover ? 1.05 : 1.0, anchor: .trailing)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0), value: listenHover)
            }

            // Contents
            if listenMode == .inactive {
                Button(action: { if !isDragging { onListen() } }) {
                    WaveformView(isActive: false)
                        .frame(width: 20, height: 16)
                        .foregroundStyle(Color.white)
                        .frame(width: itemSize, height: itemSize, alignment: .center)
                        .contentShape(Rectangle())
                        .scaleEffect(listenHover ? 1.05 : 1.0, anchor: .trailing)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0), value: listenHover)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            } else {
                HStack(spacing: spacing) {
                    // Pause/Resume
                    Button(action: {
                        if !isDragging {
                            if OverlayStateManager.shared.isPausedListening {
                                OverlayStateManager.shared.resumeListening()
                            } else {
                                OverlayStateManager.shared.pauseListening()
                            }
                        }
                    }) {
                        Image(systemName: OverlayStateManager.shared.isPausedListening ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 16)
                            .frame(width: itemSize, height: itemSize, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Stop
                    Button(action: { if !isDragging { OverlayStateManager.shared.stopListening() } }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 16)
                            .frame(width: itemSize, height: itemSize, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(height: itemSize)
                .transition(.opacity)
            }
        }
        .frame(width: listenMode == .active ? expandedWidth : collapsedWidth, height: itemSize, alignment: .trailing)
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.fast) { listenHover = hovering }
            // Tooltip for Listen (only when inactive)
            if hovering && listenMode == .inactive {
                DispatchQueue.main.async {
                    if let overlayWindow = WindowOrchestrator.shared.buttonsWindow {
                        // Derive listen button X from hide button position
                        let overlayWidth = CGFloat(layoutManager.getOverlayButtonsWidth())
                        let hideButtonX = overlayWidth - 30.0
                        let listenButtonX = hideButtonX - 6.0 - collapsedWidth
                        let listenButtonY: CGFloat = 18.0
                        let buttonFrame = CGRect(x: listenButtonX, y: listenButtonY, width: collapsedWidth, height: itemSize)
                        let screenPosition = overlayWindow.convertToScreen(buttonFrame).origin
                        TooltipWindowManager.shared.showTooltip(text: "Listen", at: screenPosition, parentWindow: overlayWindow, placeBelow: true)
                    }
                }
            } else {
                TooltipWindowManager.shared.hideTooltip()
            }
        }
        .accessibilityLabel(listenMode == .active ? "Listening controls" : "Start listening")
    }
    
    private var hideButton: some View {
        Button(action: {
            if !isDragging {
                onHide()
            }
        }) {
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 20, height: 16)
                .padding(5)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .scaleEffect(hideHover ? 1.05 : 1.0)
                .animation(DesignSystem.Animation.spring, value: hideHover)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.fast) {
                hideHover = hovering
            }
            
            // Show/hide tooltip using separate window
            if hovering {
                // Get button position in screen coordinates
                DispatchQueue.main.async {
                    // Find the actual overlay window (buttons window)
                    if let overlayWindow = WindowOrchestrator.shared.buttonsWindow {
                        // Calculate hide button position - it's the rightmost button
                        let overlayWidth = CGFloat(layoutManager.getOverlayButtonsWidth())
                        let hideButtonX = overlayWidth - 30.0 // Hide button is 30px from right edge
                        let hideButtonY: CGFloat = 18.0 // Center vertically in 36px height overlay
                        let buttonFrame = CGRect(x: hideButtonX, y: hideButtonY, width: 30.0, height: 26.0)
                        let screenPosition = overlayWindow.convertToScreen(buttonFrame).origin
                        TooltipWindowManager.shared.showTooltip(text: "⌘ + \\", at: screenPosition, parentWindow: overlayWindow)
                    }
                }
            } else {
                TooltipWindowManager.shared.hideTooltip()
            }
        }
        .accessibilityLabel("Hide overlay")
    }
    
    
    
}

// MARK: - ShortcutTooltip (unchanged)
struct ShortcutTooltip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
    }
}

// MARK: - WaveformView (Timeline-driven smooth wave)
struct WaveformView: View {
    let isActive: Bool
    let barCount: Int = 3

    var body: some View {
        if isActive {
            // Animated waveform when active
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.5) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let freq = 1.8 + Double(i) * 0.5
                        let phase = t * freq + Double(i) * 0.6
                        let amp = (sin(phase) * 0.5 + 0.5) // 0..1
                        let minH: CGFloat = 3
                        let maxH: CGFloat = 12
                        let height = minH + CGFloat(amp) * (maxH - minH)

                        let baseOpacity = max(0.0, min(1.0, 0.85 - Double(i) * 0.05 + (amp * 0.15)))
                        Capsule()
                            .frame(width: 1.8, height: height)
                            .foregroundStyle(Color.white.opacity(baseOpacity))
                            .shadow(color: Color.black.opacity(0.1 * amp), radius: 1, x: 0, y: 0)
                            .offset(y: CGFloat(-amp * 1.2))
                    }
                }
                .frame(height: 14, alignment: .center)
            }
        } else {
            // Static waveform when inactive
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let heights: [CGFloat] = [3, 8, 4]
                    Capsule()
                        .frame(width: 1.8, height: heights[i])
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .frame(height: 14, alignment: .center)
        }
    }
}


