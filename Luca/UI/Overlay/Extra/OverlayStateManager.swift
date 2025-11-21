import SwiftUI
import Combine

/// Simplified OverlayStateManager for multi-window architecture
/// Focuses on window visibility states instead of resize states
class OverlayStateManager: ObservableObject {
    static let shared = OverlayStateManager()
    
    // MARK: - Window Visibility States
    @Published var isButtonsWindowVisible: Bool = false
    @Published var isChatWindowVisible: Bool = false
    @Published var isListenWindowVisible: Bool = false
    
    // MARK: - Core UI States
    @Published var chatMode: ChatMode = .hidden
    @Published var listenMode: ListenMode = .inactive
    @Published var isPausedListening: Bool = false
    
    // MARK: - Input States
    @Published var overlayInputText: String = ""
    @Published var chatInputText: String = ""
    @Published var isInputFocused: Bool = false
    
    // MARK: - Loading States
    @Published var isLoading: Bool = false
    @Published var loadingType: LoadingType = .none
    
    // MARK: - Session States
    @Published var currentListenSessionId: String?
    
    // MARK: - Listen Button Cooldown
    @Published var isListenButtonDisabled: Bool = false
    private var listenCooldownTimer: Timer?
    
    // MARK: - Input Field Cooldown
    @Published var isInputFieldDisabled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupStateObservers()
    }
    
    // MARK: - Window Visibility Management
    
    func showButtonsWindow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isButtonsWindowVisible = true
        }
    }
    
    func hideButtonsWindow() {
        isButtonsWindowVisible = false
    }
    
    func showChatWindow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChatWindowVisible = true
            chatMode = .visible
        }
    }
    
    func hideChatWindow() {
        isChatWindowVisible = false
        chatMode = .hidden
    }
    
    func showListenWindow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isListenWindowVisible = true
            listenMode = .active
            isPausedListening = false
        }
    }
    
    func hideListenWindow() {
        isListenWindowVisible = false
        listenMode = .inactive
        isPausedListening = false
    }
    
    func hideAllWindows() {
        isButtonsWindowVisible = false
        isChatWindowVisible = false
        isListenWindowVisible = false
        chatMode = .hidden
        listenMode = .inactive
    }
    
    // MARK: - State Machine Logic (Simplified)
    
    func startListening() {
        print("🎤 OverlayStateManager.startListening() called")
        
        // Start cooldown period to prevent multiple clicks
        startListenCooldown()
        
        withAnimation(.easeInOut(duration: 0.2)) {
            listenMode = .active
            isListenWindowVisible = true
            isPausedListening = false
        }
        
        // Directly start audio capture instead of relying on notifications
        print("🎤 Starting audio capture directly...")
        Task { @MainActor in
            let sessionId = UUID().uuidString
            currentListenSessionId = sessionId
            
            if AppConfig.isCloudDeployed {
                print("☁️ Using cloud deployment path")
                // Use direct ClientAPI for cloud deployment
                ClientAPI.shared.listenStart(preferredSource: "mic") { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let serverSessionId):
                            print("✅ Listen session started successfully: \(serverSessionId)")
                            self.currentListenSessionId = serverSessionId
                            SessionTranscriptStore.shared.startListenSession(serverSessionId)
                            AudioCaptureManager.shared.startListening(sessionId: serverSessionId) { success in
                                if !success { 
                                    print("❌ Audio capture failed")
                                } else {
                                    print("✅ Audio capture started successfully")
                                }
                            }
                        case .failure(let error):
                            print("❌ Listen start failed: \(error)")
                        }
                    }
                }
            } else {
                print("🏠 Using local deployment path")
                // Use local ListenAPI for local deployment
                let listenAPI = ListenAPI.shared
                listenAPI.startSession(sessionId: sessionId)
            }
        }
        
        // Also notify MainChatView as backup
        print("📤 Posting StartListening notification")
        NotificationCenter.default.post(name: NSNotification.Name("StartListening"), object: nil)
    }
    
    func stopListening() {
        let startTime = Date()
        print("🛑 OverlayStateManager.stopListening() called")
        
        // Cancel cooldown when stopping
        cancelListenCooldown()
        
        listenMode = .inactive
        isListenWindowVisible = false
        isPausedListening = false
        
        // Directly stop audio capture
        print("🛑 Stopping audio capture directly...")
        Task { @MainActor in
            let audioStart = Date()
            await AudioCaptureManager.shared.stopListening()
            let audioTime = Date().timeIntervalSince(audioStart)
            print("✅ AudioCaptureManager.stopListening() completed in \(String(format: "%.2f", audioTime))s")
            
            if AppConfig.isCloudDeployed {
                if let sessionId = currentListenSessionId {
                    ClientAPI.shared.listenStop(sessionId: sessionId) { _ in }
                }
            } else {
                ListenAPI.shared.stopSession()
            }
            
            currentListenSessionId = nil
            // Removed extra finalize to avoid double-finalize; AudioCaptureManager triggers it
        }
        
        // Also notify MainChatView as backup
        print("📤 Posting StopListening notification")
        NotificationCenter.default.post(name: NSNotification.Name("StopListening"), object: nil)
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("✅ OverlayStateManager.stopListening() completed in \(String(format: "%.2f", totalTime))s")
    }

    // MARK: - Pause / Resume controls
    func pauseListening() {
        if listenMode == .active {
            print("⏸️ Pausing listening")
            isPausedListening = true
        }
    }

    func resumeListening() {
        if listenMode == .active {
            print("▶️ Resuming listening")
            isPausedListening = false
        }
    }
    
    func showChat() {
        showChatWindow()
    }
    
    func hideChat() {
        hideChatWindow()
    }
    
    func startLoading(_ type: LoadingType) {
        withAnimation(.easeInOut(duration: 0.1)) {
            isLoading = true
            loadingType = type
        }
    }
    
    func stopLoading() {
        withAnimation(.easeInOut(duration: 0.1)) {
            isLoading = false
            loadingType = .none
        }
    }
    
    
    func clearInput() {
        overlayInputText = ""
        chatInputText = ""
    }
    
    
    // MARK: - Private Methods
    
    private func setupStateObservers() {
        // No more complex state observers needed
        // Window visibility is managed directly
    }
    
    // MARK: - Listen Button Cooldown Management
    
    private func startListenCooldown() {
        // Disable button immediately
        isListenButtonDisabled = true
        
        // Cancel any existing timer
        listenCooldownTimer?.invalidate()
        
        // Start 2-second cooldown timer
        listenCooldownTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isListenButtonDisabled = false
                print("🔄 Listen button cooldown ended - button re-enabled")
            }
        }
        
        print("⏱️ Listen button cooldown started - button disabled for 2 seconds")
    }
    
    func cancelListenCooldown() {
        listenCooldownTimer?.invalidate()
        listenCooldownTimer = nil
        isListenButtonDisabled = false
        print("❌ Listen button cooldown cancelled")
    }
    
    // MARK: - Input Field Cooldown Management
    
    func startInputCooldown() {
        isInputFieldDisabled = true
        print("⏰ Input field disabled - waiting for response")
    }
    
    func endInputCooldown() {
        isInputFieldDisabled = false
        print("✅ Input field re-enabled - response received")
    }
    
    // MARK: - Legacy Compatibility (for existing code)
    
    /// Legacy property - returns if any window is visible
    var overlayMode: OverlayMode {
        return isButtonsWindowVisible ? .compact : .compact
    }
    
    /// Legacy property - returns fixed panel height
    var panelHeight: CGFloat {
        return 40 // Fixed buttons height
    }
    
    /// Legacy property - returns fixed panel width
    var panelWidth: CGFloat {
        return 370 // Fixed buttons width
    }
    
    /// Legacy property - returns input mode
    var inputMode: InputMode {
        return .overlay
    }
    
    /// Legacy property - returns animation state
    var isAnimating: Bool {
        return false // No more complex animations
    }
    
    /// Legacy property - returns animation type
    var animationType: AnimationType {
        return .none
    }
}

// MARK: - State Enums (Simplified)

enum OverlayMode {
    case compact // Only mode in multi-window architecture
}

enum ChatMode {
    case hidden
    case visible
    case inputOnly
}

enum ListenMode {
    case inactive
    case active
}

enum InputMode {
    case overlay
    case chat
    case inline
}

enum AnimationType {
    case none
    case slide
    case fade
    case scale
}

enum LoadingType {
    case none
    case message
    case listen
    case capture
}

/*
REMOVED FROM ORIGINAL OverlayStateManager.swift:

1. Complex state coordination:
   - updateOverlayMode() logic
   - updatePanelDimensions() logic
   - setupStateObservers() complex logic
   - Publishers.CombineLatest3 state observers

2. Resize-related states:
   - panelHeight (dynamic calculation)
   - panelWidth (dynamic calculation)
   - Complex dimension updates

3. Animation complexity:
   - isAnimating (complex state)
   - animationType (complex coordination)

These are now handled by:
- WindowOrchestrator (window positioning and visibility)
- Fixed dimensions (no more dynamic calculations)
- Simplified state management (just visibility flags)
- Direct window control (no complex state coordination)
*/