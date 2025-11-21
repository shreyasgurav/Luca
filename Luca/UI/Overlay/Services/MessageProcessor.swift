import Foundation

class MessageProcessor {
    static let shared = MessageProcessor()
    private init() {}
    private func shouldReturnTableForComparison(_ text: String) -> Bool {
        let lower = text.lowercased()
        let triggers = [
            "difference between",
            "compare",
            "comparison",
            "vs",
            "versus"
        ]
        return triggers.contains { lower.contains($0) }
    }
    
    // Smart context selection: only include transcript for relevant messages
    private func shouldIncludeTranscriptForMessage(_ message: String, transcript: String) -> Bool {
        // Early return if transcript is empty
        guard !transcript.isEmpty else { return false }
        
        let lowercasedMessage = message.lowercased()
        
        // Keywords that suggest the user wants meeting context
        let contextKeywords = [
            "meeting", "discussion", "talked about", "mentioned", "said", "presented",
            "agenda", "topic", "point", "issue", "problem", "solution", "decision",
            "summary", "recap", "overview", "what did", "what was", "who said",
            "action item", "next step", "follow up", "deadline", "timeline"
        ]
        
        // Check if message contains context keywords (more efficient)
        let hasContextKeywords = contextKeywords.contains { keyword in
            lowercasedMessage.contains(keyword)
        }
        
        // Include transcript if:
        // 1. Message has context keywords, OR
        // 2. Message is very short (likely a follow-up question), OR
        // 3. Message contains question words
        let isShortMessage = message.count < 50
        let hasQuestionWords = ["what", "who", "when", "where", "why", "how", "did", "was", "were", "is", "are"].contains { word in
            lowercasedMessage.hasPrefix(word)
        }
        
        return hasContextKeywords || isShortMessage || hasQuestionWords
    }
    
    func processMessage(
        text: String,
        conversationStore: ConversationStore,
        requestId: UUID,
        onComplete: @escaping () -> Void
    ) {
        // Start loading animation
        OverlayStateManager.shared.startLoading(.message)
        
        let lastAssistant = conversationStore.lastAssistantMessage()
        let decision = ScreenshotDecisionEngine.decide(for: text, lastAssistant: lastAssistant)
        print("🔍 MessageProcessor: Decision for '\(text)' -> \(decision)")

        // Force transcript-first, text-only path for recap/what-to-say
        let lower = text.lowercased()
        let forceTextOnly = lower.contains("recap") || lower.contains("what should i say") || lower.contains("what to say")
        if forceTextOnly {
            print("🎯 MessageProcessor: Forcing text-only path (special intent)")
            handleTextOnlyMessage(text: text, conversationStore: conversationStore, onComplete: {
                OverlayStateManager.shared.stopLoading()
                onComplete()
            })
            return
        }

        switch decision {
        case .forceCapture:
            handleForceCapture(text: text, conversationStore: conversationStore, onComplete: {
                OverlayStateManager.shared.stopLoading()
                onComplete()
            })
            
        case .probeCapture:
            handleProbeCapture(text: text, conversationStore: conversationStore, onComplete: {
                OverlayStateManager.shared.stopLoading()
                onComplete()
            })
            
        case .noCapture:
            handleTextOnlyMessage(text: text, conversationStore: conversationStore, onComplete: {
                OverlayStateManager.shared.stopLoading()
                onComplete()
            })
        }
    }
    
    private func handleForceCapture(
        text: String,
        conversationStore: ConversationStore,
        onComplete: @escaping () -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            let threadContext = conversationStore.buildContext()
            var enrichedPrompt = threadContext.isEmpty ? text : (threadContext + "\n\nUser: " + text)
            if enrichedPrompt.count > 3500 { enrichedPrompt = String(enrichedPrompt.suffix(3500)) }

            let screenshotData = ScreenshotManager.captureFullScreen(excludeWindow: ResponseOverlay.shared.panel)
            DispatchQueue.main.async {
                if let data = screenshotData {
                    AnalyzeAPI.upload(imageData: data, includeOCR: FeatureFlags.ocrEnabled, sessionId: "", prompt: enrichedPrompt) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let reply): 
                                conversationStore.appendAssistant(reply, hasScreenshot: true)
                            case .failure(let err): 
                                conversationStore.appendAssistant("❌ " + err.localizedDescription)
                            }
                            onComplete()
                        }
                    }
                } else {
                    conversationStore.appendAssistant("I couldn't capture your screen. Please enable screen recording permission.")
                    onComplete()
                }
            }
        }
    }
    
    private func handleProbeCapture(
        text: String,
        conversationStore: ConversationStore,
        onComplete: @escaping () -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            let threadContext = conversationStore.buildContext()
            var enrichedPrompt = threadContext.isEmpty ? text : (threadContext + "\n\nUser: " + text)
            if enrichedPrompt.count > 3500 { enrichedPrompt = String(enrichedPrompt.suffix(3500)) }

            print("🔍 MessageProcessor ProbeCapture: Running probe for message: '\(text)'")
            let probeResult = ScreenshotManager.probeScreenForUsefulness(excludeWindow: ResponseOverlay.shared.panel)
            print("🔍 MessageProcessor ProbeCapture result: useful=\(probeResult.useful), reason=\(probeResult.reason)")
            
            DispatchQueue.main.async {
                if probeResult.useful {
                    Task { @MainActor in
                        let screenshotData = ScreenshotManager.captureFullScreen(excludeWindow: ResponseOverlay.shared.panel)
                        DispatchQueue.main.async {
                            if let data = screenshotData {
                                AnalyzeAPI.upload(imageData: data, includeOCR: FeatureFlags.ocrEnabled, sessionId: "", prompt: enrichedPrompt) { result in
                                    DispatchQueue.main.async {
                                        switch result {
                                        case .success(let reply): 
                                            conversationStore.appendAssistant(reply, hasScreenshot: true)
                                        case .failure(let err): 
                                            conversationStore.appendAssistant("❌ " + err.localizedDescription)
                                        }
                                        onComplete()
                                    }
                                }
                            } else {
                                conversationStore.appendAssistant("I couldn't capture your screen. Please enable screen recording permission.")
                                onComplete()
                            }
                        }
                    }
                } else {
                    conversationStore.appendAssistant("I couldn't find any notable content on your screen (" + probeResult.reason + "). Do you want me to capture it anyway?")
                    onComplete()
                }
            }
        }
    }
    
    private func handleTextOnlyMessage(
        text: String,
        conversationStore: ConversationStore,
        onComplete: @escaping () -> Void
    ) {
        // Process text message normally (location features removed)

        fallbackChat(text: text, conversationStore: conversationStore, onComplete: onComplete)
    }
    
    private func fallbackChat(
        text: String,
        conversationStore: ConversationStore,
        onComplete: @escaping () -> Void
    ) {
        let threadContext = conversationStore.buildContext()
        let isListenActive = (SessionTranscriptStore.shared.currentListenSession != nil)
        
        if isListenActive {
            // Process transcript asynchronously to prevent main thread blocking
            Task { @MainActor in
                await processListenModeMessage(
                    text: text,
                    threadContext: threadContext,
                    conversationStore: conversationStore,
                    onComplete: onComplete
                )
            }
            return
        }

        // Non-listen mode: process normally
        let enriched = threadContext.isEmpty ? text : (threadContext + "\n\nUser: " + text)
        ClientAPI.shared.chat(message: enriched, sessionId: "") { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let reply):
                    conversationStore.appendAssistant(reply)
                case .failure(let error):
                    conversationStore.appendAssistant("❌ Error: \(error.localizedDescription)")
                }
                onComplete()
            }
        }
    }
    
    @MainActor
    private func processListenModeMessage(
        text: String,
        threadContext: String,
        conversationStore: ConversationStore,
        onComplete: @escaping () -> Void
    ) async {
        print("🚀 MessageProcessor: Starting listen mode message processing for: '\(text.prefix(50))...'")
        
        // Yield to prevent blocking the main thread
        await Task.yield()
        
        let currentSessionId = SessionTranscriptStore.shared.currentListenSession
        // Prefer a recency window for "what should I say"; otherwise use full rolling transcript
        let lowercased = text.lowercased()
        let isRecapRequest = lowercased.contains("recap") || lowercased.contains("summary")
        let isWhatToSayRequest =
            lowercased.contains("what should i say") ||
            lowercased.contains("what to say") ||
            lowercased.contains("say next") ||
            lowercased.contains("how should i respond") ||
            lowercased.contains("how to respond") ||
            lowercased.contains("suggest reply")
        let transcriptText: String = {
            if isWhatToSayRequest {
                // Slightly expand window to retain immediate context while staying focused
                return SessionTranscriptStore.shared.getRecentListenTranscriptWindow(maxSeconds: 90, maxChars: 1200)
            } else {
                return SessionTranscriptStore.shared.getCurrentListenTranscript()
            }
        }()
        
        print("📝 MessageProcessor: Transcript length: \(transcriptText.count) chars")
        
        // Detect special intents to force-include transcript and use lightweight chat path
        
        // Smart context selection: include transcript if relevant OR always for recap/what-to-say
        let shouldIncludeTranscript = (isRecapRequest || isWhatToSayRequest) || shouldIncludeTranscriptForMessage(text, transcript: transcriptText)
        
        print("🎯 MessageProcessor: Should include transcript: \(shouldIncludeTranscript)")
        
        // Build message composition efficiently
        var composed = ""
        
        if shouldIncludeTranscript && !transcriptText.isEmpty {
            // Budgets by intent: large for recap, small for what-to-say (slightly increased)
            let budget = isRecapRequest ? 6000 : (isWhatToSayRequest ? 1400 : 2000)
            let transcriptLength = transcriptText.count
            let startIndex = max(0, transcriptLength - budget)
            let limitedTranscript = String(transcriptText.dropFirst(startIndex))
            let header = (isRecapRequest || isWhatToSayRequest) ? "[Current Meeting Transcript]" : "[Current Meeting Context]"
            composed = "\(header)\n\(limitedTranscript)\n\n"
            print("📄 MessageProcessor: Including transcript context (\(limitedTranscript.count) chars, header=\(header))")
        }
        
        // For what-to-say, avoid older thread context to keep focus strictly on latest transcript
        if !isWhatToSayRequest, !threadContext.isEmpty {
            composed += threadContext + "\n\n"
        }
        if isWhatToSayRequest {
            // Do not add a user line; keep prompt minimal under transcript
        } else {
            composed += "User: " + text
        }

        // Add intent-specific instruction to steer backend behavior while keeping UI minimal
        if isRecapRequest {
            composed += "\n\n[Instruction: Provide a concise bullet-point recap of this session based only on the transcript above. Focus on decisions, action items, owners, and dates. Return 5-8 bullets. No preface or closing text.]"
        } else if isWhatToSayRequest {
            // Detect personal questions aimed at the user (not the AI)
            let recentLower = transcriptText.lowercased()
            let personalPatterns = [
                "tell me about yourself",
                "tell me about you",
                "about yourself",
                "about you",
                "what are your hobbies",
                "your hobbies",
                "what do you do",
                "where are you from",
                "introduce yourself",
                "who are you",
                "what's your background",
                "what is your background"
            ]
            let isPersonal = personalPatterns.contains { recentLower.contains($0) }

            // If personal, fetch profile-related memories and include as explicit context
            var profileBlock = ""
            if isPersonal {
                // Fetch on a detached task to avoid blocking UI systems; return plain String
                let profileContext: String = await Task.detached(priority: .utility) {
                    await VectorMemoryManager.shared.getRelevantMemoriesWithContext(
                        for: "user profile: bio, background, profession, interests, hobbies, preferences, location",
                        sessionId: currentSessionId
                    )
                }.value
                let trimmedProfile = profileContext.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedProfile.isEmpty {
                    profileBlock = "[User Profile: \(trimmedProfile)]\n\n"
                }
            }

            composed += profileBlock
            if isPersonal {
                composed += "Answer the most recent question in the transcript above as the USER speaking in first-person (\"I\"). Use details from the User Profile if available. Keep it 1–3 concise sentences. Output only the answer."
            } else {
                composed += "Answer the most recent question in the transcript above in 1–2 concise sentences. Output only the answer."
            }
        }
        
        print("📤 MessageProcessor: Sending message to ClientAPI (total length: \(composed.count) chars)")
        // Debug: show composed prompt for what-to-say/recap to verify context
        if isWhatToSayRequest || isRecapRequest {
            let maxPreview = 4000
            let preview = composed.count > maxPreview ? (String(composed.prefix(maxPreview)) + "\n...[truncated]\n") : composed
            print("🧪 Debug Prompt (\(isWhatToSayRequest ? "WhatToSay" : "Recap")):\n\(preview)")
        }
        
        // Make API call — for recap/what-to-say requests, skip memory extraction path
        let call: (@escaping (Result<String, Error>) -> Void) -> Void = { completion in
            if isRecapRequest || isWhatToSayRequest {
                ClientAPI.shared.chatWithoutMemoryExtraction(message: composed, sessionId: currentSessionId, completion: completion)
            } else {
                ClientAPI.shared.chat(message: composed, sessionId: currentSessionId, completion: completion)
            }
        }
        
        // Avoid messaging a deallocated store if the overlay closed mid-request
        weak var weakStore = conversationStore
        call { result in
            DispatchQueue.main.async {
                guard let store = weakStore else {
                    print("⚠️ MessageProcessor: conversationStore deallocated before reply; dropping response")
                    onComplete(); return
                }
                switch result {
                case .success(let reply):
                    store.appendAssistant(reply)
                case .failure(let error):
                    store.appendAssistant("❌ Error: \(error.localizedDescription)")
                }
                onComplete()
            }
        }
    }
    
}




