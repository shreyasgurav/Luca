import SwiftUI

// MARK: - Loading Animation Component
struct LoadingDots: View {
    @State private var animateScale: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animateScale ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animateScale
                    )
            }
        }
        .onAppear {
            animateScale = true
        }
    }
}

// MARK: - Chat Message Bubble Component
struct ModernChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 20) }
            
            HStack(alignment: .top) {
                Group {
                    if message.isUser {
                        Text(message.content)
                            .font(.system(size: 14))
                    } else {
                        MessageRenderer(message: message)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    message.isUser ?
                    AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                    AnyShapeStyle(Color.black.opacity(0.5))
                )
                .foregroundColor(message.isUser ? .white : DesignSystem.Colors.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .textSelection(.enabled)
            }
            
            if !message.isUser { Spacer(minLength: 20) }
        }
    }
}

// MARK: - Inline Input Component
struct InlineInputView: View {
    @Binding var input: String
    @Binding var isLoading: Bool
    @FocusState.Binding var focused: Bool
    let onSend: () -> Void
    
    // Responsive layout
    @StateObject private var layoutManager = OverlayLayoutManager.shared
    
    var body: some View {
        UnifiedInputField(
            text: $input,
            isFocused: $focused,
            placeholder: "Ask a question...",
            onSubmit: onSend,
            style: .inline,
            isLoading: isLoading
        )
        .padding(.horizontal, 8)
    }
}


// MARK: - Full Chat View Component
struct FullChatView: View {
    @ObservedObject var conversationStore: ConversationStore
    @Binding var isLoading: Bool
    @Binding var showChat: Bool
    let chatFeedHeight: CGFloat
    let onClear: () -> Void
    
    @State private var isClearButtonHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            clearButtonRow
            chatMessagesArea
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(DesignSystem.Colors.panelBackground)
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large).stroke(DesignSystem.Colors.borderColor, lineWidth: 1))
        )
        .standardCornerRadius(.large)
    }
    
    private var clearButtonRow: some View {
        Group {
            if (!conversationStore.messages.isEmpty || showChat) && !isLoading {
                HStack {
                    Spacer()
                    Button(action: onClear) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                            Text("Clear")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isClearButtonHovered ? DesignSystem.Colors.hoverBackground : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isClearButtonHovered = hovering
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
    
    private var chatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if conversationStore.messages.isEmpty && !isLoading {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        Spacer()
                        
                        ForEach(conversationStore.messages) { message in
                            ModernChatBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading {
                        HStack {
                                LoadingDots()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .id("loading")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: chatFeedHeight)
            .onChange(of: conversationStore.messages.count) { _ in
                if let lastMessage = conversationStore.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) { loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("Start a conversation")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Ask me anything about your screen or start listening for audio")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Expanded Chat View Component
struct ExpandedChatView: View {
    @ObservedObject var conversationStore: ConversationStore
    @Binding var userInput: String
    @Binding var isLoading: Bool
    let onSendMessage: () -> Void
    let onClose: () -> Void
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            chatScrollView
            inputArea
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                isInputFocused = true
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image("LucaLogoBlack")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                
                Text("Luca Chat")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if conversationStore.messages.isEmpty && !isLoading {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        Spacer()
                        
                        ForEach(conversationStore.messages) { message in
                            ModernChatBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading {
                            HStack {
                                LoadingDots()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(DesignSystem.Colors.hoverBackground)
                            )
                            .id("loading")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: conversationStore.messages.count) { _ in
                if let lastMessage = conversationStore.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) { loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var inputArea: some View {
        HStack(spacing: 8) {
            UnifiedInputField(
                text: $userInput,
                isFocused: $isInputFocused,
                placeholder: "Type your message...",
                onSubmit: onSendMessage,
                style: .full,
                isLoading: isLoading
            )
            
            Button(action: onSendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Welcome to Luca Chat")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("Start a conversation by typing a message below")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
