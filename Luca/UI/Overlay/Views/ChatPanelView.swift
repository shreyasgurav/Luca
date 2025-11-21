import SwiftUI

/// Chat Panel - Fixed size window containing the chat conversation history
/// Uses the original FullChatView UI design
struct ChatPanelView: View {
    @ObservedObject var conversationStore: ConversationStore
    @StateObject private var stateManager = OverlayStateManager.shared
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    @State private var isClearButtonHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            clearButtonRow
            chatMessagesArea
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(width: 500, height: 300) // Fixed dimensions
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
        )
        .standardCornerRadius(.large)
    }
    
    private var clearButtonRow: some View {
        Group {
            if (!conversationStore.messages.isEmpty || stateManager.chatMode == .visible) {
                HStack {
                    // Live transcription context indicator
                    if transcriptStore.currentListenSession != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text("Ask about meeting")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(DesignSystem.Colors.primary.opacity(0.2))
                        )
                    }
                    
                    Spacer()
                    
                    Button(action: hideChat) {
                        Text("Clear")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isClearButtonHovered ? Color.white.opacity(0.10) : Color.clear)
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
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        messagesList
                        loadingIndicator
                    }
                    .frame(minHeight: geometry.size.height)
                    .background(Color.clear)
                }
                .background(Color.clear)
            }
            .frame(maxHeight: 250) // Fixed height for chat area
            .onChange(of: conversationStore.messages.count) { _ in
                scrollToLatestMessage(proxy: proxy)
            }
            .onChange(of: stateManager.isLoading) { _ in
                scrollToLoadingIndicator(proxy: proxy)
            }
        }
    }
    
    private var messagesList: some View {
        ForEach(conversationStore.messages) { message in
            HStack {
                if message.isUser { Spacer(minLength: 40) }
                ModernChatBubble(message: message)
                    .background(Color.clear)
                if !message.isUser { Spacer(minLength: 40) }
            }
            .id(message.id)
        }
    }
    
    private var loadingIndicator: some View {
        Group {
            if stateManager.isLoading {
                HStack {
                    VStack(alignment: .leading) {
                        HStack { LoadingDots() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    Spacer(minLength: 40) // Push to left side like AI messages
                }
                .id("loading")
            }
        }
    }
    
    private func scrollToLatestMessage(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let last = conversationStore.messages.last {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func scrollToLoadingIndicator(proxy: ScrollViewProxy) {
        if stateManager.isLoading {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("loading", anchor: .bottom)
            }
        }
    }
    
    // MARK: - Actions
    
    private func hideChat() {
        // Clear all chat messages to start fresh conversation
        conversationStore.clear()
        
        // Clear any loading state
        stateManager.stopLoading()
        
        // Hide the chat panel
        WindowOrchestrator.shared.hideChat()
    }
}

// MARK: - Components imported from ChatComponents.swift
// ModernChatBubble and LoadingDots are defined in ChatComponents.swift