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
                    // Compact Mode with inline chat (no expand)
                    CompactView(
                        onAskQuestion: {},
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
        ConversationManager.shared.addUser(messageText)
        
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

        // If message appears to be a nearby/open-now intent and we have location, call places
        if isNearbyIntent(messageText), let coord = LocationManager.shared.lastCoordinate {
            let q = extractPlacesQuery(from: messageText)
            ClientAPI.shared.placesSearch(query: q, lat: coord.latitude, lng: coord.longitude, radius: 3000, openNow: true) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success(let resp):
                        if resp.results.isEmpty {
                            self.fallbackChat(messageText)
                        } else {
                            let top = resp.results.prefix(5).enumerated().map { idx, r in
                                let open = (r.open_now == true) ? "(open now)" : ""
                                let dist = r.distance_m != nil ? " - \(r.distance_m!)m" : ""
                                return "\(idx+1). \(r.name) \(open)\(dist)\n   \(r.address ?? "")\n   Maps: \(r.apple_maps_url ?? r.google_maps_url ?? "")"
                            }.joined(separator: "\n\n")
                            self.conversation.append(ChatMessage(content: "Here are nearby options:\n\n" + top, isUser: false))
                        }
                    case .failure:
                        self.fallbackChat(messageText)
                    }
                }
            }
            return
        }

        // Include recent thread context like ChatGPT
        let threadContext = ConversationManager.shared.recentThreadContext()
        let enriched = threadContext.isEmpty ? messageText : (threadContext + "\n\nUser: " + messageText)
        ClientAPI.shared.chat(message: enriched, sessionId: SessionManager.shared.currentSessionId) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let reply):
                    self.conversation.append(ChatMessage(content: reply, isUser: false))
                    ConversationManager.shared.addAssistant(reply)
                case .failure(let error):
                    self.conversation.append(ChatMessage(content: "❌ Error: \(error.localizedDescription)", isUser: false))
                }
            }
        }
    }



    private func fallbackChat(_ messageText: String) {
        let threadContext = ConversationManager.shared.recentThreadContext()
        let enriched = threadContext.isEmpty ? messageText : (threadContext + "\n\nUser: " + messageText)
        ClientAPI.shared.chat(message: enriched, sessionId: SessionManager.shared.currentSessionId) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let reply):
                    self.conversation.append(ChatMessage(content: reply, isUser: false))
                    ConversationManager.shared.addAssistant(reply)
                case .failure(let error):
                    self.conversation.append(ChatMessage(content: "❌ Error: \(error.localizedDescription)", isUser: false))
                }
            }
        }
    }

    private func isNearbyIntent(_ text: String) -> Bool {
        let t = text.lowercased()
        let keys = ["near me", "nearby", "closest", "open now", "around me", "near"]
        return keys.contains { t.contains($0) }
    }

    private func extractPlacesQuery(from text: String) -> String {
        // Heuristic: use the noun before/after nearby keywords
        let t = text.lowercased()
        if t.contains("salon") || t.contains("saloon") { return "salon" }
        if t.contains("barber") { return "barber" }
        if t.contains("restaurant") || t.contains("dinner") { return "restaurant" }
        if t.contains("coffee") || t.contains("cafe") { return "coffee" }
        if t.contains("pharmacy") { return "pharmacy" }
        if t.contains("gym") { return "gym" }
        return text
    }
}

struct CompactView: View {
    let onAskQuestion: () -> Void
    let onHide: () -> Void
    @State private var isListening: Bool = false
    @State private var listeningSessionId: String = ""
    @State private var startTime: Date?
    @State private var timer: Timer? = nil
    @State private var now: Date = Date()
    @State private var pulseScale: CGFloat = 1.0
    @State private var localTranscript: String = ""
    @State private var ocrEnabled: Bool = true
    @State private var showInlineChat: Bool = false
    @State private var inlineInput: String = ""
    @State private var inlineConversation: [ChatMessage] = []
    @State private var inlineLoading: Bool = false
    @State private var inlineChatSessionId: UUID = UUID()
    @FocusState private var inlineFocused: Bool
    
        var body: some View {
        VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
			// Listen Button FIRST
			Button(action: toggleListening) {
				HStack(spacing: 6) {
					if isListening {
						Image(systemName: "record.circle.fill")
							.font(.system(size: 12, weight: .medium))
							.foregroundColor(.white)
						Text(startTime.map { listeningDuration(from: $0) } ?? "00:00")
							.font(.system(size: 12, weight: .semibold))
							.monospacedDigit()
							.minimumScaleFactor(0.9)
							.lineLimit(1)
					} else {
						Image(systemName: "waveform")
							.font(.system(size: 12, weight: .medium))
						Text("Listen")
							.font(.system(size: 12, weight: .semibold))
							.minimumScaleFactor(0.9)
							.lineLimit(1)
					}
				}
				.frame(minWidth: 100)
				.foregroundColor(.white)
				.padding(.horizontal, 16)
				.padding(.vertical, 8)
				.background(
					LinearGradient(
						colors: isListening ? [.red, .pink] : [.purple, .indigo],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
				.clipShape(Capsule())
				.shadow(color: (isListening ? Color.red : Color.purple).opacity(0.3), radius: 4, x: 0, y: 2)
			}
			.buttonStyle(.plain)

			// Ask Question SECOND → shows one-shot inline input below
			Button(action: {
				withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
					showInlineChat = true
					let frame = ResponseOverlay.shared.panel?.frame ?? .zero
					let newHeight: CGFloat = 300
					ResponseOverlay.shared.panel?.setFrame(CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: newHeight), display: true, animate: true)
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
					inlineFocused = true
					ResponseOverlay.shared.panel?.makeKey()
				}
			}) {
				HStack(spacing: 6) {
					Image(systemName: "text.bubble")
						.font(.system(size: 12, weight: .medium))
					Text("Ask Question")
						.font(.system(size: 12, weight: .semibold))
						.minimumScaleFactor(0.9)
						.lineLimit(1)
				}
				.frame(minWidth: 130)
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
						.padding(.horizontal, 18)
						.padding(.vertical, 8)
						.background(.ultraThinMaterial)
						.overlay(
							Capsule()
								.stroke(Color.white.opacity(0.2), lineWidth: 1)
						)
						.clipShape(Capsule())
						.frame(minWidth: 90)
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
        .padding(.top, 12)
        
		if !inlineConversation.isEmpty || inlineLoading || showInlineChat {
			VStack(spacing: 8) {
				// Chat header with Clear button
				HStack {
					Spacer()
					Button(action: { clearInlineChat() }) {
						Text("Clear")
							.font(.system(size: 11, weight: .semibold))
						.foregroundColor(.secondary)
						.padding(.horizontal, 10)
						.padding(.vertical, 6)
						.background(.ultraThinMaterial)
						.clipShape(Capsule())
					}
					.buttonStyle(.plain)
				}
				.padding(.top, 8)
                // Mini conversation feed
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(inlineConversation.enumerated()), id: \.offset) { _, m in
                            HStack {
                                if m.isUser { Spacer(minLength: 40) }
                                ModernChatBubble(message: m)
                                if !m.isUser { Spacer(minLength: 40) }
                            }
                        }
						if inlineLoading {
							HStack {
								// Assistant thinking bubble with three animated dots
								VStack(alignment: .leading) {
									HStack {
										LoadingDots()
									}
								}
								.background(Color.white.opacity(0.08))
								.clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.leading, 0)
								Spacer()
							}
						}
                    }
                }
				.frame(height: 150)

				if showInlineChat && !inlineLoading {
					HStack(spacing: 8) {
						TextField("Ask a question...", text: $inlineInput)
							.textFieldStyle(.plain)
							.padding(.horizontal, 10)
							.frame(height: 28)
							.background(
								RoundedRectangle(cornerRadius: 8)
									.fill(.ultraThinMaterial)
									.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
							)
							.focused($inlineFocused)
							.onSubmit { inlineSend() }
						Button(action: { inlineSend() }) {
							Image(systemName: "arrow.up")
								.font(.system(size: 12, weight: .semibold))
								.foregroundColor(.white)
								.frame(width: 26, height: 26)
								.background(Circle().fill(.ultraThinMaterial))
								.clipShape(Circle())
						}
						.buttonStyle(.plain)
						.disabled(inlineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.bottom, 10)
			.background(
				RoundedRectangle(cornerRadius: 14)
					.fill(.ultraThinMaterial)
					.overlay(
						RoundedRectangle(cornerRadius: 14)
							.stroke(Color.white.opacity(0.18), lineWidth: 1)
					)
			)
			.clipShape(RoundedRectangle(cornerRadius: 14))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        }
        .onAppear {
            pulseScale = 1.05
            
            // Listen for ask question and clear chat triggers from global shortcuts
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ExecuteAskQuestion"),
                object: nil,
                queue: .main
            ) { _ in
                self.triggerAskQuestionProgrammatically()
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ExecuteClearChat"),
                object: nil,
                queue: .main
            ) { _ in
                self.triggerClearChatProgrammatically()
            }
        }
		// Timer now appears inside the Listen capsule; removed floating overlay
    }

    private func listeningDuration(from start: Date) -> String {
        let s = Int(now.timeIntervalSince(start))
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    private func toggleListening() {
        if isListening {
            guard !listeningSessionId.isEmpty else { isListening = false; return }
            ClientAPI.shared.listenStop(sessionId: listeningSessionId) { result in
                DispatchQueue.main.async {
						if case .success(let obj) = result {
							let sid = listeningSessionId.isEmpty ? (obj["sessionId"] as? String ?? UUID().uuidString) : listeningSessionId
							let serverTranscript = (obj["transcript"] as? String) ?? ""
							// Prefer local on-device transcript; if server only returned mock and local is empty, save a helpful placeholder file
							let serverIsMock = serverTranscript.contains("[mock transcript") || serverTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
							let localHasText = !localTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
							let savedChunks = (obj["stats"] as? [String: Any])? ["chunks"] as? Int ?? 0
							if localHasText {
								// Add the transcript to the current session
								SessionTranscriptStore.shared.addFinalTranscript(localTranscript)
								ResponseOverlay.shared.show(text: "📝 Session saved (\(savedChunks) chunks). Using on-device transcript (\(localTranscript.count) chars)")
							} else if serverIsMock {
								let placeholder = """
								[No system audio detected]
								To capture YouTube/Zoom audio:
								1) Install BlackHole (2ch)
								2) Open Audio MIDI Setup → Create Multi‑Output (Speakers + BlackHole)
								3) System Settings → Sound → Output: Multi‑Output, Input: BlackHole 2ch
								Then press Listen again.
								"""
								SessionTranscriptStore.shared.addFinalTranscript(placeholder)
								ResponseOverlay.shared.show(text: "📝 Session saved (placeholder). Configure Multi‑Output + BlackHole to capture system audio.")
							} else {
								SessionTranscriptStore.shared.addFinalTranscript(serverTranscript)
								ResponseOverlay.shared.show(text: "📝 Session saved (\(savedChunks) chunks).")
							}
						} else {
							// Network/stop error: still save local if present, otherwise save placeholder guidance
							let sid = listeningSessionId.isEmpty ? UUID().uuidString : listeningSessionId
							let localText = localTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
							if !localText.isEmpty {
								SessionTranscriptStore.shared.addFinalTranscript(localText)
								ResponseOverlay.shared.show(text: "📝 Session saved.")
							} else {
								let placeholder = """
								[No system audio detected]
								To capture YouTube/Zoom audio:
								1) Install BlackHole (2ch)
								2) Open Audio MIDI Setup → Create Multi‑Output (Speakers + BlackHole)
								3) System Settings → Sound → Output: Multi‑Output, Input: BlackHole 2ch
								Then press Listen again.
								"""
								SessionTranscriptStore.shared.addFinalTranscript(placeholder)
								ResponseOverlay.shared.show(text: "📝 Session saved (placeholder). Configure Multi‑Output + BlackHole to capture system audio.")
							}
						}
                }
            }
            AudioCaptureManager.shared.stopListening() {}
            SpeechTranscriber.shared.stop()
            ScreenOCRManager.shared.stop()
            isListening = false
            listeningSessionId = ""
            startTime = nil
            timer?.invalidate(); timer = nil
        } else {
            ClientAPI.shared.listenStart { result in
                switch result {
                case .success(let sid):
                    listeningSessionId = sid
                    startTime = Date()
                    // Start mic capture and parallel on-device streaming transcription for real-time text
                    localTranscript = ""
                    // Professional approach: Screen Recording permission handles system audio automatically
                    ResponseOverlay.shared.show(text: "🎧 Professional Audio Capture Enabled\n\nSystem audio (YouTube, Zoom, etc.) will be captured automatically via Screen Recording permission.\n\nNo external drivers or manual setup required!")
                    SpeechTranscriber.shared.start(onPartial: { partial in
                        // accumulate partials lightly (only last 5 seconds worth)
                        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !p.isEmpty {
                            localTranscript = localTranscript
                                .split(separator: "\n")
                                .filter { !$0.hasPrefix("[partial]") }
                                .joined(separator: "\n")
                            localTranscript += (localTranscript.isEmpty ? "" : "\n") + "[partial] " + p
                        }
                    }, onFinal: { finalText in
                        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
                        // remove existing partial line and append final
                        localTranscript = localTranscript
                            .split(separator: "\n")
                            .filter { !$0.hasPrefix("[partial]") }
                            .joined(separator: "\n")
                        localTranscript += (localTranscript.isEmpty ? "" : "\n") + finalText
                    })

                    if ocrEnabled {
                        ScreenOCRManager.shared.start(captureEvery: 1.0, excludeWindow: ResponseOverlay.shared.panel) { text in
                            let stamped = "[screen] " + text
                            localTranscript += (localTranscript.isEmpty ? "" : "\n") + stamped
                        }
                    }

                    AudioCaptureManager.shared.startListening(sessionId: sid) { okMic in
                        DispatchQueue.main.async {
                            isListening = okMic
                            if okMic {
                                timer?.invalidate()
                                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in now = Date() }
                            } else {
                                ResponseOverlay.shared.show(text: "🎤 Can't access mic or start audio. Check mic permission in System Settings > Privacy & Security > Microphone.")
                            }
                        }
                    }
                case .failure:
                    break
                }
            }
        }
    }

    private func inlineSend() {
        let text = inlineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !inlineLoading else { return }
        inlineLoading = true
        let requestId = UUID()
        inlineChatSessionId = requestId
        inlineConversation.append(ChatMessage(content: text, isUser: true))
        inlineInput = ""
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showInlineChat = false }

        // Route intent centrally to keep behavior consistent
        let lastAssistant = inlineConversation.last(where: { !$0.isUser })?.content
        switch IntentRouter.route(for: text, lastAssistantMessage: lastAssistant) {
        case .screenshot(let prompt):
            DispatchQueue.main.async {
                let screenshotData = ScreenshotManager.captureFullScreen(excludeWindow: ResponseOverlay.shared.panel)
                if let data = screenshotData {
                    AnalyzeAPI.upload(imageData: data, includeOCR: FeatureFlags.ocrEnabled, sessionId: SessionManager.shared.currentSessionId, prompt: prompt) { result in
                        DispatchQueue.main.async {
                            guard self.inlineChatSessionId == requestId else { return }
                            inlineLoading = false
                            switch result {
                            case .success(let reply):
                                inlineConversation.append(ChatMessage(content: reply, isUser: false, hasScreenshot: true))
                            case .failure(let err):
                                inlineConversation.append(ChatMessage(content: "❌ " + err.localizedDescription, isUser: false))
                            }
                            let frame = ResponseOverlay.shared.panel?.frame ?? .zero
                            let hasFeed = !inlineConversation.isEmpty
                            let newHeight: CGFloat = hasFeed ? 220 : 120
                            ResponseOverlay.shared.panel?.setFrame(CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: newHeight), display: true, animate: true)
                        }
                    }
                } else {
                    // Fallback to text-only if screenshot fails
                    self.inlineSendTextOnly(text: prompt, requestId: requestId)
                }
            }

        case .places(let query):
            self.inlineSendTextOnly(text: query, requestId: requestId)
        case .plainChat(let message):
            self.inlineSendTextOnly(text: message, requestId: requestId)
        }
    }

    private func inlineSendTextOnly(text: String, requestId: UUID) {
        ClientAPI.shared.chat(message: text, sessionId: SessionManager.shared.currentSessionId) { result in
            DispatchQueue.main.async {
                guard self.inlineChatSessionId == requestId else { return }
                inlineLoading = false
                switch result {
                case .success(let reply):
                    inlineConversation.append(ChatMessage(content: reply, isUser: false))
                case .failure(let err):
                    inlineConversation.append(ChatMessage(content: "❌ " + err.localizedDescription, isUser: false))
                }
                let frame = ResponseOverlay.shared.panel?.frame ?? .zero
                let hasFeed = !inlineConversation.isEmpty
                let newHeight: CGFloat = hasFeed ? 220 : 120
                ResponseOverlay.shared.panel?.setFrame(CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: newHeight), display: true, animate: true)
                
                // Auto-refocus input after response
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    inlineFocused = true
                }
            }
        }
    }

    private func clearInlineChat() {
        inlineConversation.removeAll()
        inlineInput = ""
        inlineLoading = false
        inlineChatSessionId = UUID() // invalidate any in-flight request handlers
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showInlineChat = false }
        let frame = ResponseOverlay.shared.panel?.frame ?? .zero
        ResponseOverlay.shared.panel?.setFrame(CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: 120), display: true, animate: true)
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
    
    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 50) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Group {
                        if message.isUser {
                            Text(message.content)
                                .font(.system(size: 14))
                        } else {
                            MarkdownRendererView(text: message.content)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser ?
                        AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                        AnyShapeStyle(Color.black.opacity(0.8))
                    )
                    .foregroundColor(message.isUser ? .white : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
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
            Text("")
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            animateScale = true
        }
    }
}

// MARK: - ResponsePanel Extensions
extension ResponsePanel {
    mutating func forceShowInlineChat() {
        // Ensure we're in compact mode and show inline chat
        isExpanded = false
        
        // Trigger the ask question functionality directly
        // Since we can't easily access the CompactView, we'll use a different approach
        // We'll set a flag that the CompactView can check
        // For now, let's just ensure the panel is visible and focused
        ResponseOverlay.shared.panel?.makeKey()
    }
}

// MARK: - CompactView Extensions
extension CompactView {
    func triggerAskQuestionProgrammatically() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showInlineChat = true
            let frame = ResponseOverlay.shared.panel?.frame ?? .zero
            let newHeight: CGFloat = 300
            ResponseOverlay.shared.panel?.setFrame(
                CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: newHeight),
                display: true,
                animate: true
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            inlineFocused = true
            ResponseOverlay.shared.panel?.makeKey()
        }
    }
    
    func triggerClearChatProgrammatically() {
        // Clear the conversation
        inlineConversation.removeAll()
        
        // Hide the inline chat
        showInlineChat = false
        
        // Reset the panel to compact size
        let frame = ResponseOverlay.shared.panel?.frame ?? .zero
        ResponseOverlay.shared.panel?.setFrame(
            CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: 140),
            display: true,
            animate: true
        )
    }
}
