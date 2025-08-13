import AppKit
import SwiftUI
import FirebaseAuth

// Custom NSPanel subclass to handle text input properly
class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
}

struct ChatMessage {
    let content: String
    let isUser: Bool
    let timestamp: Date
    let hasScreenshot: Bool
    
    init(content: String, isUser: Bool, hasScreenshot: Bool = false) {
        self.content = content
        self.isUser = isUser
        self.hasScreenshot = hasScreenshot
        self.timestamp = Date()
    }
}

final class ResponseOverlay {
    static let shared = ResponseOverlay()
    var panel: FocusablePanel?

    func show(text: String = "") {
        DispatchQueue.main.async { [self] in
            // Check if user is authenticated
            if Auth.auth().currentUser == nil {
                MainWindow.shared.show()
                return
            }
            
            if panel == nil { createPanel() }
            if let hosting = panel?.contentViewController as? NSHostingController<ResponsePanel> {
                hosting.rootView = ResponsePanel(text: text)
                hosting.view.needsDisplay = true
            }
            panel?.orderFrontRegardless()
            panel?.center()
            
            // CRITICAL: Make panel key window for text input
            panel?.makeKey()
        }
    }
    
    func showExpandedChat() {
        DispatchQueue.main.async { [self] in
            // Check if user is authenticated
            if Auth.auth().currentUser == nil {
                MainWindow.shared.show()
                return
            }
            
            if panel == nil { createPanel() }
            if let hosting = panel?.contentViewController as? NSHostingController<ResponsePanel> {
                // Create a new ResponsePanel with expanded state
                let expandedPanel = ResponsePanel(text: "", isExpanded: true)
                hosting.rootView = expandedPanel
                hosting.view.needsDisplay = true
            }
            panel?.orderFrontRegardless()
            panel?.center()
            
            // CRITICAL: Make panel key window for text input
            panel?.makeKey()
        }
    }
    
    func hide() {
        DispatchQueue.main.async { [self] in
            panel?.orderOut(nil)
        }
    }

    private func createPanel() {
        let style: NSWindow.StyleMask = [.borderless]
        let panel = FocusablePanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 120), styleMask: style, backing: .buffered, defer: false)
        
        // Glass morphism window properties
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        
        // CRITICAL: Enable proper text input and focus handling
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.makeFirstResponder(nil)
        
        // Privacy and behavior settings
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        
        // CRITICAL: This makes the window invisible to screen capture APIs
        panel.sharingType = .none
        panel.isExcludedFromWindowsMenu = true
        panel.canBecomeVisibleWithoutLogin = true

        let vc = NSHostingController(rootView: ResponsePanel(text: ""))
        panel.contentViewController = vc
        self.panel = panel
    }
}

struct ResponsePanel: View {
    var text: String
    @State private var userInput: String = ""
    @State private var isLoading: Bool = false
    @State private var conversation: [ChatMessage] = []
    @State private var isExpanded: Bool = false
    @State private var animateGradient: Bool = false
    
    init(text: String = "", isExpanded: Bool = false) {
        self.text = text
        self._isExpanded = State(initialValue: isExpanded)
    }
    
    var body: some View {
        ZStack {
            // Conditional Background - transparent when compact, glass when expanded
            if isExpanded {
                // Liquid Glass Background with Animation
                RoundedRectangle(cornerRadius: 20)
                    .fill(.clear)
                    .background(
                        ZStack {
                            // Animated liquid background layers
                            RadialGradient(
                                colors: [Color.blue.opacity(0.4), Color.clear],
                                center: UnitPoint(x: 0.3, y: 0.2),
                                startRadius: 0,
                                endRadius: 200
                            )
                            .scaleEffect(animateGradient ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animateGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            
                            RadialGradient(
                                colors: [Color.purple.opacity(0.3), Color.clear],
                                center: UnitPoint(x: 0.7, y: 0.8),
                                startRadius: 0,
                                endRadius: 150
                            )
                            .scaleEffect(animateGradient ? 0.8 : 1.1)
                            .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animateGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            
                            RadialGradient(
                                colors: [Color.green.opacity(0.25), Color.clear],
                                center: UnitPoint(x: 0.8, y: 0.3),
                                startRadius: 0,
                                endRadius: 120
                            )
                            .scaleEffect(animateGradient ? 1.3 : 0.9)
                            .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: animateGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            
                            // Glass morphism overlay
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 8)
            } else {
                // Transparent background for compact mode
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
            }
            
            VStack(spacing: 0) {
                if !isExpanded {
                    // Compact Mode - Two buttons
                    CompactView(
                                            onAskQuestion: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            isExpanded = true
                            // Resize window
                            ResponseOverlay.shared.panel?.setFrame(
                                CGRect(x: ResponseOverlay.shared.panel?.frame.origin.x ?? 0,
                                       y: ResponseOverlay.shared.panel?.frame.origin.y ?? 0,
                                       width: 400,
                                       height: 500),
                                display: true,
                                animate: true
                            )
                            
                            // Ensure window becomes key for text input
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                ResponseOverlay.shared.panel?.makeKey()
                                ResponseOverlay.shared.panel?.makeKeyAndOrderFront(nil)
                            }
                        }
                    },
                        onHide: {
                            ResponseOverlay.shared.panel?.orderOut(nil)
                        }
                    )
                } else {
                    // Expanded Mode - Chat interface
                    ExpandedChatView(
                        conversation: $conversation,
                        userInput: $userInput,
                        isLoading: $isLoading,
                        onSendMessage: { sendMessage() },
                        onClose: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isExpanded = false
                                conversation.removeAll()
                                // Resize window back
                                ResponseOverlay.shared.panel?.setFrame(
                                    CGRect(x: ResponseOverlay.shared.panel?.frame.origin.x ?? 0,
                                           y: ResponseOverlay.shared.panel?.frame.origin.y ?? 0,
                                           width: 400,
                                           height: 120),
                                    display: true,
                                    animate: true
                                )
                            }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            animateGradient = true
        }
    }
    
    private func sendMessage() {
        guard !userInput.isEmpty, !isLoading else { return }
        let messageText = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        userInput = ""
        isLoading = true
        
        // Add user message to conversation
        conversation.append(ChatMessage(content: messageText, isUser: true))
        
        // Check if message asks about screen content - be more specific
        let needsScreenshot = messageText.lowercased().contains("screen") || 
                             messageText.lowercased().contains("what's on") ||
                             messageText.lowercased().contains("whats on") ||
                             messageText.lowercased().contains("see on") ||
                             messageText.lowercased().contains("on my screen") ||
                             messageText.lowercased().contains("what is on") ||
                             messageText.lowercased().contains("show me")
        
        if needsScreenshot {
            print("📸 Taking screenshot for question: \(messageText)")
            
            // Take screenshot on main thread
            DispatchQueue.main.async {
                let screenshotData = ScreenshotManager.captureFullScreen(excludeWindow: ResponseOverlay.shared.panel)
                
                if let imageData = screenshotData {
                    // Send with screenshot
                    ClientAPI.shared.uploadAndAnalyze(imageData: imageData, includeOCR: false, sessionId: SessionManager.shared.currentSessionId, customPrompt: messageText) { result in
                        DispatchQueue.main.async {
                            self.isLoading = false
                            switch result {
                            case .success(let reply):
                                self.conversation.append(ChatMessage(content: reply, isUser: false, hasScreenshot: true))
                            case .failure(let error):
                                self.conversation.append(ChatMessage(content: "❌ Error: \(error.localizedDescription)", isUser: false))
                            }
                        }
                    }
                } else {
                    // Fallback to text-only if screenshot fails
                    self.sendTextOnlyMessage(messageText)
                }
            }
        } else {
            // Send text-only message
            sendTextOnlyMessage(messageText)
        }
    }
    
    private func sendTextOnlyMessage(_ messageText: String) {
        ClientAPI.shared.chat(message: messageText, sessionId: SessionManager.shared.currentSessionId) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let reply):
                    self.conversation.append(ChatMessage(content: reply, isUser: false))
                case .failure(let error):
                    self.conversation.append(ChatMessage(content: "❌ Error: \(error.localizedDescription)", isUser: false))
                }
            }
        }
    }
}

struct CompactView: View {
    let onAskQuestion: () -> Void
    let onHide: () -> Void
    @State private var pulseScale: CGFloat = 1.0
    
        var body: some View {
        HStack(spacing: 8) {
                    // Nova Logo
        Image("NovaLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
            
            // Ask Question Button
            Button(action: onAskQuestion) {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12, weight: .medium))
                    Text("Ask Question")
                        .font(.system(size: 12, weight: .semibold))
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .scaleEffect(pulseScale)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseScale)
            
            // Action Buttons (Hide and Settings)
            HStack(spacing: 8) {
                // Hide Button
                Button(action: onHide) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .medium))
                        Text("Hide")
                            .font(.system(size: 12, weight: .semibold))
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                // Settings Button
                Button(action: {
                    MainWindow.shared.show()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .onAppear {
            pulseScale = 1.05
        }
    }
}

struct ExpandedChatView: View {
    @Binding var conversation: [ChatMessage]
    @Binding var userInput: String
    @Binding var isLoading: Bool
    let onSendMessage: () -> Void
    let onClose: () -> Void
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image("NovaLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .shadow(color: .blue.opacity(0.2), radius: 2, x: 0, y: 1)
                    
                    Text("Nova")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
            )
            
            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(conversation.enumerated()), id: \.offset) { index, message in
                            ModernChatBubble(message: message)
                                .id(index)
                        }
                        
                        // Loading indicator
                        if isLoading {
                            HStack {
                                LoadingDots()
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .onChange(of: conversation.count) { _ in
                    if let lastIndex = conversation.indices.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area - Made more compact
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(userInput.isEmpty ? Color.white.opacity(0.2) : Color.blue.opacity(0.5), lineWidth: 1)
                            )
                            .frame(height: 32)
                        
                        TextField("Ask a question...", text: $userInput)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .lineLimit(1)
                            .disabled(isLoading)
                            .onSubmit { onSendMessage() }
                            .focused($isInputFocused)
                            .allowsHitTesting(true)
                            .onTapGesture {
                                isInputFocused = true
                                // Force window to become key when text field is tapped
                                DispatchQueue.main.async {
                                    ResponseOverlay.shared.panel?.makeKey()
                                }
                            }
                    }
                    
                    Button(action: onSendMessage) {
                        Image(systemName: isLoading ? "hourglass" : "arrow.up")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(
                                userInput.isEmpty || isLoading ?
                                AnyShapeStyle(Color.secondary.opacity(0.3)) :
                                AnyShapeStyle(LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            )
                            .clipShape(Circle())
                            .rotationEffect(.degrees(isLoading ? 180 : 0))
                            .animation(.easeInOut(duration: 0.3), value: isLoading)
                    }
                    .buttonStyle(.plain)
                    .disabled(userInput.isEmpty || isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            // Auto-focus the input when expanded view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                ResponseOverlay.shared.panel?.makeKey()
                isInputFocused = true
            }
        }
    }
}

struct ModernChatBubble: View {
    let message: ChatMessage
    @State private var showCopyButton: Bool = false
    
    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 50) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack {
                    Text(message.content)
                        .font(.system(size: 14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            message.isUser ?
                            AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                            AnyShapeStyle(Color.white.opacity(0.1))
                        )
                        .foregroundColor(message.isUser ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCopyButton = hovering && !message.isUser
                            }
                        }
                    
                    // Copy button for AI responses - always reserve space
                    if !message.isUser {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .opacity(showCopyButton ? 1.0 : 0.0)
                        }
                        .buttonStyle(.plain)
                        .disabled(!showCopyButton)
                    }
                }
                
                HStack(spacing: 4) {
                    if message.hasScreenshot {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text("Screenshot analyzed")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            if !message.isUser { Spacer(minLength: 50) }
        }
    }
}

struct LoadingDots: View {
    @State private var animateScale: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animateScale ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animateScale
                    )
            }
            Text("")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            animateScale = true
        }
    }
}
