import SwiftUI
import AVFoundation

/// Listen Panel - Fixed size window containing the listen/transcription interface
/// Uses the original ListenChatPanel UI design
struct ListenPanelView: View {
    @StateObject private var stateManager = OverlayStateManager.shared
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    @State private var notesText: String = ""
    @State private var showingTranscriptions = false
    @State private var isButtonHovered = false
    @State private var showMicMenu = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Chat content area
            chatContentView
            
            // Footer with controls
            footerView
        }
        .frame(width: 320, height: 300)
        // Use natural spacing; avoid negative offsets that pull content too high
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
        )
        .standardCornerRadius(.large)
    }
    
    private var headerView: some View {
        HStack(alignment: .top) {
            // Left corner - Title
            Text(showingTranscriptions ? "Transcriptions" : "Notes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Toggle button
            Button(action: {
                showingTranscriptions.toggle()
            }) {
                HStack(spacing: 4) {
                    if !showingTranscriptions {
                        WaveformView(isActive: false)
                            .frame(width: 12, height: 8)
                    } else {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                    
                    Text(showingTranscriptions ? "Notes" : "Transcriptions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isButtonHovered ? Color.white.opacity(0.10) : Color.clear)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isButtonHovered = hovering
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Allow drag gestures to pass through to parent
                    }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    private var chatContentView: some View {
        VStack(spacing: 0) {
            if showingTranscriptions {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            transcriptionsView
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color.clear)
                    .onChange(of: transcriptStore.segmentsCount) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: transcriptStore.livePartialTranscript) { _ in
                        if !transcriptStore.livePartialTranscript.isEmpty {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                // Notes: no outer ScrollView; the NSScrollView inside handles scrolling
                notesView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onAppear {
                        notesText = UserDefaults.standard.string(forKey: "ListenPanelNotes") ?? ""
                    }
                    .onChange(of: transcriptStore.currentListenSession) { sessionId in
                        // Clear notes when a new session starts
                        if sessionId != nil {
                            notesText = ""
                        }
                    }
            }
        }
        .padding(.top, 4)
    }
    
    private var notesView: some View {
        ZStack(alignment: .topLeading) {
            TransparentTextEditor(text: $notesText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: notesText) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "ListenPanelNotes")
                }

            if notesText.isEmpty {
                Text("Write notes here…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 10)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Transparent Text Editor (macOS)
    struct TransparentTextEditor: NSViewRepresentable {
        @Binding var text: String

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.borderType = .noBorder
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.verticalScroller?.knobStyle = .light
            scrollView.horizontalScroller?.knobStyle = .light

            let textView = NSTextView()
            textView.isEditable = true
            textView.isRichText = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = true
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            // Keep explicit colors; avoid adaptive remapping that can wash out text
            textView.usesAdaptiveColorMappingForDarkAppearance = false
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            textView.textColor = .white
            textView.font = NSFont.systemFont(ofSize: 12)
            textView.insertionPointColor = .white
            textView.typingAttributes = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
            textView.string = text
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textView.textContainer?.widthTracksTextView = true
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.delegate = context.coordinator

            scrollView.documentView = textView

            // Store reference for coordinator
            context.coordinator.textView = textView
            context.coordinator.scrollView = scrollView

            return scrollView
        }

        func updateNSView(_ nsView: NSScrollView, context: Context) {
            guard let textView = context.coordinator.textView else { return }
            if textView.string != text {
                let selected = textView.selectedRange()
                textView.string = text
                if selected.location <= text.count {
                    textView.setSelectedRange(selected)
                }
            }
            // Ensure transparency and text styling persist if system toggles appearance
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            textView.textColor = .white
            textView.font = NSFont.systemFont(ofSize: 12)
            textView.insertionPointColor = .white
            // Do not reset typingAttributes here; it can disrupt live typing
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            var parent: TransparentTextEditor
            weak var textView: NSTextView?
            weak var scrollView: NSScrollView?

            init(_ parent: TransparentTextEditor) {
                self.parent = parent
            }

            func textDidChange(_ notification: Notification) {
                guard let tv = textView ?? notification.object as? NSTextView else { return }
                // Update binding on main to sync placeholder and content immediately
                DispatchQueue.main.async { self.parent.text = tv.string }
                // Keep typing attributes consistent
                tv.typingAttributes = [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular)
                ]
            }
            
            func textViewDidChangeSelection(_ notification: Notification) {
                guard let tv = notification.object as? NSTextView else { return }
                tv.insertionPointColor = .white
            }
        }
    }
    
    private var transcriptionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !transcriptStore.hasSegments && transcriptStore.livePartialTranscript.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    
                    Text("Start system audio to see transcriptions here")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white)
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
                    HStack {
                        Spacer()
                        LiveTranscriptBubble(
                            text: transcriptStore.livePartialTranscript,
                            isReceiving: transcriptStore.isReceivingPartialTranscript
                        )
                        Spacer()
                    }
                }
                
                // Bottom anchor for auto-scrolling
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
        }
    }
    
    private var footerView: some View {
        Group {
            if !showingTranscriptions && transcriptStore.currentListenSession != nil {
                HStack(spacing: 12) {
                    Spacer()
                    
                    Button(action: {
                        generateRecap()
                    }) {
                        Text("Recap")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        generateWhatToSay()
                    }) {
                        Text("What should I say?")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
    
    // MARK: - Actions
    
    private func askQuestion(_ question: String) {
        // Show chat window with the suggested question
        WindowOrchestrator.shared.showChat(with: question)
    }
    
    private func generateRecap() {
        // Show chat window with a minimal recap request (backend adds transcript + instruction)
        WindowOrchestrator.shared.showChat(with: "Recap")
        
        print("📝 Recap requested for session: \(transcriptStore.currentListenSession ?? "unknown")")
    }
    
    private func generateWhatToSay() {
        // Show chat window with a minimal what-to-say request (backend adds transcript + instruction)
        WindowOrchestrator.shared.showChat(with: "What should I say?")
        
        print("💬 What to say requested for session: \(transcriptStore.currentListenSession ?? "unknown")")
    }
    
}

// MARK: - Components imported from ListenChatPanel.swift
// LiveTranscriptBubble, TranscriptBubble, and SuggestionButton are defined in ListenChatPanel.swift