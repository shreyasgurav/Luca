import SwiftUI

/// Simplified MainChatView - No resize logic, delegates to WindowOrchestrator
/// This view is now primarily used for legacy compatibility
struct MainChatView: View {
    @ObservedObject var conversationStore: ConversationStore
    let onAskQuestion: () -> Void
    let onHide: () -> Void

    // Centralized state management
    @StateObject private var stateManager = OverlayStateManager.shared
    
    // API services (for listen functionality)
    @StateObject private var listenAPI = ListenAPI.shared
    @StateObject private var audioCapture = AudioCaptureManager.shared
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    
    var body: some View {
        // This view now just delegates to WindowOrchestrator
        // The actual UI is handled by separate panel views
        Color.clear
            .frame(width: 370, height: 40) // Match buttons panel size
        .onAppear {
            setupNotifications()
            setupListenAPI()
            }
    }
    
    // MARK: - Notification Setup
    
    private func setupNotifications() {
        print("🔔 Setting up MainChatView notifications...")
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ExecuteAskQuestion"), object: nil, queue: .main) { _ in
            print("📨 Received ExecuteAskQuestion notification")
            handleAskQuestion()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ExecuteClearChat"), object: nil, queue: .main) { _ in
            print("📨 Received ExecuteClearChat notification")
            clearChat()
        }
        
        // Listen for listen mode changes
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StartListening"), object: nil, queue: .main) { _ in
            print("📨 Received StartListening notification")
            handleStartListening()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StopListening"), object: nil, queue: .main) { _ in
            print("📨 Received StopListening notification")
            handleStopListening()
        }
        
        print("✅ MainChatView notifications set up successfully")
    }
    
    // MARK: - Actions
    
    private func handleAskQuestion() {
        // Show chat window through WindowOrchestrator
        WindowOrchestrator.shared.showChat()
    }
    
    private func clearChat() {
        conversationStore.clear()
        stateManager.clearInput()
        stateManager.stopLoading()
        stateManager.chatMode = .hidden
    }
    
    private func handleStartListening() {
        print("🎤 Starting listen session...")
        print("🔧 AppConfig.isCloudDeployed: \(AppConfig.isCloudDeployed)")
        print("🌐 Server URL: \(AppConfig.serverBaseURL)")
        
        if AppConfig.isCloudDeployed {
            print("☁️ Using cloud deployment path")
            // Use direct ClientAPI for cloud deployment (like the old working code)
            ClientAPI.shared.listenStart(preferredSource: "mic") { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let sessionId):
                        print("✅ Listen session started successfully: \(sessionId)")
                        self.stateManager.currentListenSessionId = sessionId
                        self.transcriptStore.startListenSession(sessionId)
                        self.audioCapture.startListening(sessionId: sessionId) { success in
                            if !success { 
                                print("❌ Audio capture failed")
                                self.handleListenError("Failed to start audio capture") 
                            } else {
                                print("✅ Audio capture started successfully")
                            }
                        }
                    case .failure(let error):
                        print("❌ Listen start failed: \(error)")
                        self.handleListenError("Start failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            print("🏠 Using local deployment path")
            // Use local ListenAPI for local deployment
            let sessionId = UUID().uuidString
            listenAPI.startSession(sessionId: sessionId)
        }
    }
    
    private func handleStopListening() {
        print("🛑 Stopping listen session...")
        
        Task { await audioCapture.stopListening() }
        
        if AppConfig.isCloudDeployed {
            if let sessionId = stateManager.currentListenSessionId {
                ClientAPI.shared.listenStop(sessionId: sessionId) { _ in }
            }
            stateManager.currentListenSessionId = nil
        } else {
            listenAPI.stopSession()
            stateManager.currentListenSessionId = nil
        }
        
        // Do not call finalize here; AudioCaptureManager.finishSession handles it
    }
    
    // MARK: - Listen API Setup (simplified)
    
    private func setupListenAPI() {
        if AppConfig.isCloudDeployed {
            print("📡 Using direct Deepgram integration")
        } else {
            listenAPI.onSessionStarted = { sessionId in
                DispatchQueue.main.async {
                    print("🎤 Listen session started: \(sessionId)")
                    stateManager.currentListenSessionId = sessionId
                    transcriptStore.startListenSession(sessionId)
                    audioCapture.startListening(sessionId: sessionId) { success in
                        if !success { self.handleListenError("Failed to start audio capture") }
                    }
                }
            }
            listenAPI.onTranscriptionUpdate = { text, _ in
                DispatchQueue.main.async {
                    print("🎯 Transcription update: \(text)")
                    transcriptStore.addListenTranscriptSegment(text, isPartial: false)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showTranscriptInChat(text)
                    }
                }
            }
            listenAPI.onSessionCompleted = { _, _ in
                DispatchQueue.main.async {
                    print("🛑 Listen session completed")
                    transcriptStore.finalizeListenSession()
                    stateManager.currentListenSessionId = nil
                    let finalTranscript = transcriptStore.getCurrentListenTranscript()
                    if !finalTranscript.isEmpty { showFinalTranscript(finalTranscript) }
                }
            }
            listenAPI.onError = { error in
                DispatchQueue.main.async {
                    print("❌ Listen error: \(error)")
                    self.handleListenError(error)
                }
            }
        }
    }
    
    // MARK: - Listen Helpers
    
    private func showTranscriptInChat(_ text: String) {
        conversationStore.appendUser("🎤 \(text)")
        if stateManager.chatMode != .visible && stateManager.chatMode != .inputOnly {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                stateManager.chatMode = .visible
            }
            // Show chat window instead of resizing
            WindowOrchestrator.shared.showChat()
        }
    }
    
    private func showFinalTranscript(_ transcript: String) {
        conversationStore.appendUser("🎤 Listening session completed:\n\n\(transcript)")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            stateManager.chatMode = .visible
        }
        // Show chat window instead of resizing
        WindowOrchestrator.shared.showChat()
    }
    
    private func handleListenError(_ error: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            stateManager.stopListening()
        }
        conversationStore.appendAssistant("❌ Listen error: \(error)")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            stateManager.chatMode = .visible
        }
        // Show chat window instead of resizing
        WindowOrchestrator.shared.showChat()
        Task { await audioCapture.stopListening() }
        stateManager.currentListenSessionId = nil
        // Removed extra finalize to avoid double-finalize
    }
}

// MARK: - Removed Components (no longer needed in multi-window architecture)

/*
REMOVED FROM ORIGINAL MainChatView.swift:

1. All resize-related state variables:
   - buttonRowHeight
   - isAdjustingFrame  
   - pendingResizeWorkItem
   - basePanelHeight
   - chatFeedHeight (dynamic calculation)

2. All resize-related methods:
   - setPanelHeightKeepingTop()
   - adjustPanelFrameForCurrentState()
   - scheduleAdjustedResize()
   - applyFrameSafely()

3. All complex layout logic:
   - shouldShowChatOverlay
   - chatOverlayView
   - Complex frame calculations
   - Screen boundary checks
   - Width/height adjustments

4. All resize-related onChange handlers:
   - onChange(of: stateManager.chatMode)
   - onChange(of: stateManager.listenMode)
   - onChange(of: stateManager.isLoading)
   - onChange(of: conversationStore.messages.count)

5. Complex UI rendering:
   - OverlayButtons integration
   - ListenChatPanel integration
   - InlineInputView integration
   - FullChatView integration

These are now handled by:
- ButtonsPanelView.swift (OverlayButtons)
- ChatPanelView.swift (FullChatView, InlineInputView)
- ListenPanelView.swift (ListenChatPanel)
- WindowOrchestrator.swift (positioning and coordination)
*/