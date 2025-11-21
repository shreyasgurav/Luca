import SwiftUI
import AppKit

/// Button that distinguishes between clicks and drags
struct DragAwareButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    
    @State private var isDragging: Bool = false
    @State private var dragStartLocation: CGPoint = .zero
    private let dragThreshold: CGFloat = 3.0
    
    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }
    
    var body: some View {
        Button(action: {
            // Only trigger action if we didn't drag
            if !isDragging {
                action()
            }
        }) {
            label()
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                        if distance > dragThreshold {
                            isDragging = true
                        }
                    }
                }
                .onEnded { _ in
                    // Small delay to allow button action to check isDragging state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        isDragging = false
                    }
                }
        )
    }
}

/// Buttons Panel - Fixed size window containing only the overlay buttons
struct ButtonsPanelView: View {
    @StateObject private var stateManager = OverlayStateManager.shared
    @State private var listenHover: Bool = false
    @State private var logoHover: Bool = false
    @State private var hideHover: Bool = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            // Left: Luca logo
            lucaLogo
            
            // Center: Input field with placeholder
            ZStack(alignment: .leading) {
                if stateManager.overlayInputText.isEmpty {
                    Text("Ask anything...")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.leading, 0)
                        .animation(DesignSystem.Animation.fast, value: stateManager.overlayInputText.isEmpty)
                }
                TextField("", text: $stateManager.overlayInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .accentColor(DesignSystem.Colors.primary)
                    .focused($isInputFocused)
                    .disabled(stateManager.isInputFieldDisabled)
                    .opacity(stateManager.isInputFieldDisabled ? 0.6 : 1.0)
                    .onSubmit {
                        if !stateManager.overlayInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !stateManager.isInputFieldDisabled {
                            handleAskQuestion()
                        }
                    }
            }
            .scaleEffect(isInputFocused ? 1.02 : 1.0)
            .animation(DesignSystem.Animation.spring, value: isInputFocused)
            
            // Right: Listen controls and hide button
            listenControls
            hideButton
        }
                .frame(width: 320, height: 32) // Fixed dimensions
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.pill)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.pill)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
        )
        .background(WindowDragArea().allowsHitTesting(true)) // Native drag area
        .onHover { hovering in
            if hovering {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var lucaLogo: some View {
        DragAwareButton(action: {
            MainWindow.shared.focusExistingSpace()
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
            } else if let img = NSImage(contentsOfFile: "/Users/shreyasgurav/Desktop/Luca/assets/Luca Logo NoBG Black.png") {
                Image(nsImage: img)
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
                    .opacity(0.9)
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
                        let logoY: CGFloat = 16.0 // Center vertically in 32px height overlay
                        let buttonFrame = CGRect(x: logoX, y: logoY, width: 32, height: 26)
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
        let itemSize: CGFloat = 26 // Match hide button size
        let spacing: CGFloat = 0
        let collapsedWidth: CGFloat = itemSize
        let expandedWidth: CGFloat = itemSize * 2 + spacing

        return ZStack(alignment: .trailing) {
            // Background: match hide button when inactive, expand when active
            if stateManager.listenMode == .active {
                Capsule()
                    .fill(DesignSystem.Colors.error.opacity(0.25))
                    .frame(width: expandedWidth, height: itemSize)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: stateManager.listenMode)
                    .scaleEffect(1.0, anchor: .trailing) // no hover scale when active
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: collapsedWidth, height: itemSize)
                    .scaleEffect(listenHover ? 1.05 : 1.0, anchor: .trailing)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0), value: listenHover)
            }

            if stateManager.listenMode == .inactive {
                // Collapsed: waveform
                DragAwareButton(action: { if !stateManager.isListenButtonDisabled { handleListen() } }) {
                    WaveformView(isActive: false)
                        .frame(width: 20, height: 16)
                        .foregroundStyle(Color.white)
                        .frame(width: itemSize, height: itemSize, alignment: .center)
                        .contentShape(Rectangle())
                        .opacity(stateManager.isListenButtonDisabled ? 0.5 : 1.0)
                        .scaleEffect(listenHover ? 1.05 : 1.0, anchor: .trailing)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0), value: listenHover)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            } else {
                // Expanded: pause/resume + stop inside capsule
                HStack(spacing: spacing) {
                    DragAwareButton(action: {
                        if stateManager.isPausedListening { stateManager.resumeListening() } else { stateManager.pauseListening() }
                    }) {
                        Image(systemName: stateManager.isPausedListening ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 16)
                            .frame(width: itemSize, height: itemSize, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    DragAwareButton(action: {
                        stateManager.stopListening()
                        WindowOrchestrator.shared.hideListen()
                    }) {
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
        .frame(width: stateManager.listenMode == .active ? expandedWidth : collapsedWidth, height: itemSize, alignment: .trailing)
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.fast) { listenHover = hovering }
            // Tooltip for Listen (only when inactive)
            if hovering && stateManager.listenMode == .inactive {
                DispatchQueue.main.async {
                    if let overlayWindow = WindowOrchestrator.shared.buttonsWindow {
                        // Fixed overlay width for this panel
                        let overlayWidth: CGFloat = 320
                        let hideButtonX = overlayWidth - 30
                        let listenButtonX = hideButtonX - 6 - collapsedWidth
                        let listenButtonY: CGFloat = 16
                        let buttonFrame = CGRect(x: listenButtonX, y: listenButtonY, width: collapsedWidth, height: itemSize)
                        let screenPosition = overlayWindow.convertToScreen(buttonFrame).origin
                        TooltipWindowManager.shared.showTooltip(text: "Listen", at: screenPosition, parentWindow: overlayWindow, placeBelow: true)
                    }
                }
            } else {
                TooltipWindowManager.shared.hideTooltip()
            }
        }
        .accessibilityLabel(stateManager.listenMode == .active ? "Listening controls" : "Start listening")
    }
    
    private var hideButton: some View {
        DragAwareButton(action: {
            WindowOrchestrator.shared.hideAll()
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
                        // Calculate hide button position - it's the rightmost button in 320px width
                        let overlayWidth: CGFloat = 320
                        let hideButtonX = overlayWidth - 30 // Hide button is 30px from right edge
                        let hideButtonY: CGFloat = 16 // Center vertically in 32px height overlay
                        let buttonFrame = CGRect(x: hideButtonX, y: hideButtonY, width: 30, height: 26)
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
    
    // MARK: - Actions
    
    private func handleAskQuestion() {
        let text = stateManager.overlayInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !stateManager.isInputFieldDisabled else { return }
        
        // Start input cooldown to prevent multiple questions
        stateManager.startInputCooldown()
        
        // Show chat window with the question
        WindowOrchestrator.shared.showChat(with: text)
        
        // Clear input
        stateManager.overlayInputText = ""
    }
    
    private func handleListen() {
        // Don't allow action if button is disabled
        guard !stateManager.isListenButtonDisabled else {
            print("🚫 Listen button is disabled - ignoring click")
            return
        }
        
        if stateManager.listenMode == .active {
            stateManager.stopListening()
            WindowOrchestrator.shared.hideListen()
        } else {
            stateManager.startListening()
            WindowOrchestrator.shared.showListen()
        }
    }
}

// MARK: - WaveformView imported from OverlayButtons.swift
