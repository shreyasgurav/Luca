import SwiftUI

struct ListenChatPanel: View {
    @Binding var listenMode: ListenMode
    @ObservedObject var transcriptStore: SessionTranscriptStore
    let chatFeedHeight: CGFloat // Match the chat panel height
    let onAskQuestion: (String) -> Void // Callback to ask question in chat
    
    // Responsive layout
    @StateObject private var layoutManager = OverlayLayoutManager.shared
    // REMOVED suggestions system for performance
    
    // REMOVED toggle - only show transcriptions now
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Chat content area
            chatContentView
            
            // Footer with controls
            footerView
        }
        .frame(width: layoutManager.getListenPanelWidth(), height: chatFeedHeight) // Match chat panel height
        .padding(.top, -8) // Pull content closer to top edge
        // Keep panel background but remove border/shadow halo
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
        )
        .opacity(listenMode == .active ? 1.0 : 0.0)
        // Remove animations/transitions to avoid layout feedback during panel resizing
    }
    
    private var headerView: some View {
        HStack(alignment: .top) {
            // Left corner - Title
            Text("Transcriptions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, -2)
        .padding(.bottom, 6)
    }
    
    private var chatContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                transcriptionsView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 220)
            .background(Color.clear)
            .onChange(of: transcriptStore.segmentsCount) { _ in
                // Auto-scroll to bottom when new transcriptions are added
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: transcriptStore.livePartialTranscript) { _ in
                // Auto-scroll to bottom when live transcript updates
                if !transcriptStore.livePartialTranscript.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.4))
            
            Text("Ask questions to see suggestions here")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // REMOVED suggestions view for performance
    
    private var transcriptionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !transcriptStore.hasSegments && transcriptStore.livePartialTranscript.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("Start speaking to see transcriptions here")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Show completed transcript segments
                ForEach(transcriptStore.displaySegments, id: \.id) { segment in
                    TranscriptBubble(segment: segment)
                }
                
                // Show live partial transcript with clean animation
                if !transcriptStore.livePartialTranscript.isEmpty {
                    LiveTranscriptBubble(
                        text: transcriptStore.livePartialTranscript,
                        isReceiving: transcriptStore.isReceivingPartialTranscript
                    )
                }
                
                // Bottom anchor for auto-scrolling
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
        }
    }
    
    private var footerView: some View {
        EmptyView()
    }
}

// MARK: - Live Transcript Bubble Component

struct LiveTranscriptBubble: View {
    let text: String
    let isReceiving: Bool
    
    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.6)
                        )
                )
            Spacer()
        }
    }
}

struct TranscriptBubble: View {
    let segment: TranscriptSegment
    
    var body: some View {
        let isMic = (segment.source == .microphone)
        HStack(alignment: .top, spacing: 8) {
            if !isMic {
                // Left aligned (system)
                contentBubble(isMic: isMic)
                Spacer()
            } else {
                // Right aligned (microphone)
                Spacer()
                contentBubble(isMic: isMic)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func contentBubble(isMic: Bool) -> some View {
        // Match mic bubbles to user's chat message style
        let gradient = LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        let bgColor: Color = Color.white.opacity(0.12)
        let stroke: Color = Color.white.opacity(0.25)
        let textColor: Color = isMic ? .white : .white
        
        VStack(alignment: isMic ? .trailing : .leading, spacing: 2) {
            if segment.type == .partial {
                HStack(spacing: 4) {
                    if !isMic { Text("...")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.6)) }
                    Text(segment.text)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(isMic ? .white.opacity(0.95) : .white.opacity(0.9))
                }
            } else {
                Text(segment.text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(textColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if isMic {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(gradient)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(bgColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(stroke, lineWidth: 1)
                        )
                }
            }
        )
    }
}

// REMOVED SuggestionButton for performance

#Preview {
    ListenChatPanel(
        listenMode: .constant(.active),
        transcriptStore: SessionTranscriptStore.shared,
        chatFeedHeight: 300,
        onAskQuestion: { question in
            print("Asking question: \(question)")
        }
    )
    .frame(width: 400, height: 350)
    .background(Color.gray.opacity(0.2))
}
