import Foundation
import AppKit
import os.log

struct TranscriptSegment {
    let id = UUID()
    let text: String
    let timestamp: Date
    let type: TranscriptType
    let sessionId: String?
    let confidence: Float
    let source: TranscriptSource
    
    enum TranscriptType {
        case server
        case listen
        case partial
    }
    
    enum TranscriptSource: String, Codable {
        case system
        case microphone
    }
}

struct ListenSession: Equatable {
    let id: String
    let startTime: Date
    var endTime: Date?
    var segments: [TranscriptSegment]
    var summary: String?
    var title: String? // derived friendly title
    var highlights: [String] = []
    var actionItems: [String] = []
    var tags: [String] = []
    var notes: String? // Detailed notes in markdown format
    var isComplete: Bool = false // Track if session is fully processed
    var fullTranscript: String {
        segments.filter { $0.type == .listen }.map(\.text).joined(separator: " ")
    }
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    // Equatable conformance
    static func == (lhs: ListenSession, rhs: ListenSession) -> Bool {
        return lhs.id == rhs.id
    }
}

final class SessionTranscriptStore: ObservableObject, DeepgramSTTDelegate {
    static let shared = SessionTranscriptStore()
    private let logger = Logger(subsystem: "com.luca.app", category: "SessionTranscriptStore")
    
    @Published var transcripts: [String] = [] // Legacy
    @Published var segments: [TranscriptSegment] = []
    @Published var sessions: [ListenSession] = [] // New: saved sessions
    @Published var canLoadMoreSessions: Bool = true
    @Published var currentListenSession: String?
    @Published var currentListenTranscript: String = ""
    @Published var livePartialTranscript: String = "" // Real-time partial transcript
    @Published var isReceivingPartialTranscript: Bool = false // Indicates if we're receiving live updates
    @Published var generatingNotesForSessions: Set<String> = [] // Track which sessions are generating notes
    
    // Public accessors for segments (computed properties)
    var segmentsCount: Int {
        return segments.count
    }
    
    var hasSegments: Bool {
        return !segments.isEmpty
    }
    
    var displaySegments: [TranscriptSegment] {
        return segments
    }
    
    private var currentSession: ListenSession?
    private let sessionStorageService = FirestoreSessionService.shared
    
    // Chunking for vector indexing
    private var chunkBufferText: String = ""
    private var chunkBufferStartTime: Date?
    private let chunkMaxChars: Int = 800
    private let chunkMaxSeconds: TimeInterval = 30
    
    // Real-time update management
    private var partialUpdateTimer: Timer?
    private let partialUpdateDebounceInterval: TimeInterval = 0.05 // 50ms debounce for more responsive updates
    
    private init() {
        setupAuthListener()
        // Don't load sessions immediately - wait for auth state to be determined
        // loadSessionsFromStorage() will be called by handleAuthStateChange()
        
        // Trigger initial auth state check after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleAuthStateChange()
        }
    }
    
    // MARK: - User Authentication Integration
    
    private func setupAuthListener() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthStateChange),
            name: NSNotification.Name("AuthenticationStateChanged"),
            object: nil
        )
    }
    
    @MainActor
    @objc private func handleAuthStateChange() {
        print("👤 Auth state changed - reloading sessions from local storage")
        clearCurrentSession()
        
        // Check if API keys are valid before loading sessions
        Task { @MainActor in
            if APIKeyManager.shared.hasValidKeys {
                await loadSessionsFromStorage() // Reload sessions on auth change
            } else {
                print("👤 No valid API keys - clearing sessions")
                sessions = []
            }
        }
    }
    
    // MARK: - Current Session Management
    
    func clearCurrentSession() {
        segments.removeAll()
        currentListenSession = nil
        currentListenTranscript = ""
        currentSession = nil
        print("🧹 Cleared current listen session")
    }
    
    // MARK: - Local Persistence
    @MainActor
    private func loadSessionsFromStorage() async {
        // Double-check API keys before loading
        guard APIKeyManager.shared.hasValidKeys else {
            print("❌ Cannot load sessions - no valid API keys")
            sessions = []
            return
        }
        
        Task {
            do {
                sessionStorageService.resetSessionsPagination()
                let storedSessions = try await sessionStorageService.loadSessions()
                await MainActor.run {
                    self.sessions = storedSessions
                    self.canLoadMoreSessions = (storedSessions.count >= 20)
                    // Backfill missing titles deterministically so they don't keep changing
                    for index in self.sessions.indices {
                        if self.sessions[index].title == nil || self.sessions[index].title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                            self.sessions[index].title = self.generateDeterministicTitle(from: self.sessions[index])
                        }
                    }
                    print("📱 Loaded \(self.sessions.count) sessions from local storage")
                    NotificationCenter.default.post(name: NSNotification.Name("SessionsRefreshed"), object: nil)
                }
                // Trigger background backfill of legacy segments into subcollection (safe, idempotent)
                Task.detached { [sessions = storedSessions] in
                    for s in sessions { await FirestoreSessionService.shared.backfillLegacySegmentsIfNeeded(session: s) }
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to load sessions from local storage: \(error)")
                    self.sessions = []
                    self.canLoadMoreSessions = false
                    NotificationCenter.default.post(name: NSNotification.Name("SessionsRefreshed"), object: nil)
                }
            }
        }
    }

    // Public: load more sessions for pagination
    func loadMoreSessions() {
        Task {
            do {
                let more = try await sessionStorageService.loadMoreSessions()
                await MainActor.run {
                    if !more.isEmpty {
                        self.sessions.append(contentsOf: more)
                        self.canLoadMoreSessions = (more.count >= 20)
                    } else {
                        self.canLoadMoreSessions = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.canLoadMoreSessions = false
                }
            }
        }
    }
    
    private func saveSessionToStorage(_ session: ListenSession, finalTranscript: String? = nil) {
        Task {
            do {
                try await sessionStorageService.saveSession(session, finalTranscript: finalTranscript)
                print("💾 Saved session \(session.id) to local storage")
            } catch {
                print("❌ Failed to save session to local storage: \(error)")
            }
        }
    }
    
    private func updateSessionInStorage(_ session: ListenSession) {
        Task {
            do {
                try await sessionStorageService.updateSession(session)
                print("💾 Updated session \(session.id) in local storage")
            } catch {
                print("❌ Failed to update session in local storage: \(error)")
            }
        }
    }
    
    private func deleteSessionFromStorage(_ sessionId: String) {
        Task {
            do {
                try await sessionStorageService.deleteSession(sessionId)
                print("🗑️ Deleted session \(sessionId) from local storage")
            } catch {
                print("❌ Failed to delete session from local storage: \(error)")
            }
        }
    }
    
    func refreshSessions() {
        Task { @MainActor in
            await loadSessionsFromStorage()
        }
    }

    // MARK: - Public Mutations
    func updateSessionTitle(sessionId: String, to newTitle: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].title = trimmed.isEmpty ? nil : trimmed
        updateSessionInStorage(sessions[idx])
        objectWillChange.send()
    }

    // MARK: - Delete
    func deleteSession(_ session: ListenSession) {
        DispatchQueue.main.async {
            // Optimistically remove from UI immediately
            if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
                self.sessions.remove(at: index)
                print("🗑️ Optimistically removed session \(session.id) from UI")
            }
            
            // Then remove from DB (async)
            self.deleteSessionFromStorage(session.id)
        }
    }
    
    // MARK: - Legacy support
    func addServerTranscript(_ transcript: String) {
        DispatchQueue.main.async {
            self.transcripts.append(transcript)
            self.segments.append(TranscriptSegment(
                text: transcript,
                timestamp: Date(),
                type: .server,
                sessionId: nil,
                confidence: 1.0,
                source: .system
            ))
        }
    }
    
    // MARK: - Listen session management
    func startListenSession(_ sessionId: String) {
        DispatchQueue.main.async {
            // Clear all live transcript data for fresh session
            self.segments.removeAll()
            self.livePartialTranscript = ""
            self.isReceivingPartialTranscript = false
            self.currentListenTranscript = ""
            
            // Clear suggestions for fresh session (removed SuggestedQuestionsEngine)
            
            self.currentListenSession = sessionId
            self.currentSession = ListenSession(
                id: sessionId,
                startTime: Date(),
                endTime: nil,
                segments: [],
                summary: nil
            )
            print("📝 Started listen session: \(sessionId) - cleared previous transcripts and suggestions")
            
            // Reset chunk buffer
            self.chunkBufferText = ""
            self.chunkBufferStartTime = Date()
        }
    }
    
    func addListenTranscriptSegment(_ text: String, isPartial: Bool = false, source: TranscriptSegment.TranscriptSource = .system) {
        guard let sessionId = currentListenSession, !text.isEmpty else { return }
        
        DispatchQueue.main.async {
            let segment = TranscriptSegment(
                text: text,
                timestamp: Date(),
                type: isPartial ? .partial : .listen,
                sessionId: sessionId,
                confidence: 1.0,
                source: source
            )
            
            if isPartial {
                // For partial updates, replace the last partial segment
                if let lastIndex = self.segments.lastIndex(where: { $0.type == .partial && $0.sessionId == sessionId }) {
                    self.segments[lastIndex] = segment
                } else {
                    self.segments.append(segment)
                }
            } else {
                // Remove any partial segments for this session
                self.segments.removeAll { $0.type == .partial && $0.sessionId == sessionId }
                
                // Add final segment
                self.segments.append(segment)
                
                // Add to current session
                self.currentSession?.segments.append(segment)
                
                // Update current transcript
                self.currentListenTranscript += (self.currentListenTranscript.isEmpty ? "" : " ") + text
                // Append to chunk buffer and flush if needed
                self.appendToChunkBuffer(text)
            }
            
            print("📝 Added transcript: \(text.prefix(50))...")
        }
    }
    
    func finalizeListenSession() {
        guard let sessionId = currentListenSession, var session = currentSession else { return }
        
        print("🔄 Starting session finalization for: \(sessionId)")
        let startTime = Date()
        
        DispatchQueue.main.async {
            // Flush any remaining chunk before finalize
            self.flushChunkBuffer(force: true)
            // Clean up real-time update timer
            self.partialUpdateTimer?.invalidate()
            self.partialUpdateTimer = nil
            
            // Clear all live transcript data
            self.livePartialTranscript = ""
            self.isReceivingPartialTranscript = false
            self.currentListenTranscript = ""
            
            // Remove any remaining partial segments
            self.segments.removeAll { $0.type == .partial && $0.sessionId == sessionId }
            
            // Finalize the session
            session.endTime = Date()
            
            // Generate and store ALL session content once when session ends
            session.title = self.generateDeterministicTitle(from: session)
            
            // Generate title, summary, highlights, action items, detailed notes
            // Run these as background tasks to prevent UI blocking
            Task.detached(priority: .background) {
                print("🔄 Background task: Starting title generation for \(sessionId)")
                await self.generateTitleIfNeeded(for: sessionId)
                print("✅ Background task: Completed title generation for \(sessionId)")
            }
            Task.detached(priority: .background) {
                print("🔄 Background task: Starting content generation for \(sessionId)")
                await self.generateCompleteSessionContent(for: sessionId)
                print("✅ Background task: Completed content generation for \(sessionId)")
            }
            
            // Check transcript length for memory management
            let maxTranscriptLength = 50000
            if session.fullTranscript.count > maxTranscriptLength {
                print("⚠️ Large transcript detected (\(session.fullTranscript.count) chars) - consider truncating segments for memory management")
            }
            
            // Save to sessions list (but don't mark as complete yet). Ensure parent finalTranscript is set from subcollection.
            self.sessions.append(session)
            Task {
                let finalText = session.fullTranscript
                self.saveSessionToStorage(session, finalTranscript: finalText.isEmpty ? nil : String(finalText.prefix(50000)))
            }
            
            // Store final transcript in legacy format for compatibility
            if !self.currentListenTranscript.isEmpty {
                self.transcripts.append(self.currentListenTranscript)
            }
            
            // Clear segments for next session
            self.segments.removeAll()
            
            let finalizationTime = Date().timeIntervalSince(startTime)
            print("📝 Finalized listen session: \(sessionId) with \(session.segments.count) segments in \(String(format: "%.2f", finalizationTime))s")
            print("💾 Total saved sessions: \(self.sessions.count)")
            
            // All session content generation is now handled in generateCompleteSessionContent
            
            // Reset current session state
            self.currentListenSession = nil
            self.currentListenTranscript = ""
            self.currentSession = nil
            self.chunkBufferText = ""
            self.chunkBufferStartTime = nil
            self.livePartialTranscript = ""
            
            print("🧹 Memory cleanup completed for session: \(sessionId)")
        }
    }
    
    func getListenTranscript(for sessionId: String) -> String {
        let sessionSegments = segments.filter { $0.sessionId == sessionId && $0.type == .listen }
        return sessionSegments.map(\.text).joined(separator: " ")
    }
    
    func getCurrentListenTranscript() -> String {
        return currentListenTranscript
    }

    // Returns the most recent portion of the current session's transcript
    // constrained by a time window (seconds) and a character ceiling.
    func getRecentListenTranscriptWindow(maxSeconds: TimeInterval = 180, maxChars: Int = 2000) -> String {
        guard let sid = currentListenSession else { return currentListenTranscript.suffix(max(0, maxChars)).description }
        let cutoff = Date().addingTimeInterval(-maxSeconds)
        let recent = segments.filter { seg in
                seg.sessionId == sid && seg.timestamp >= cutoff && seg.type != .partial
            }
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.text }
            .joined(separator: " ")
        let withPartial: String = {
            guard isReceivingPartialTranscript, !livePartialTranscript.isEmpty else { return recent }
            return recent.isEmpty ? livePartialTranscript : (recent + " " + livePartialTranscript)
        }()
        if withPartial.isEmpty {
            // Fallback to last chars of the rolling transcript
            let t = currentListenTranscript
            if t.count <= maxChars { return t }
            return String(t.suffix(maxChars))
        }
        if withPartial.count <= maxChars { return withPartial }
        return String(withPartial.suffix(maxChars))
    }

    // MARK: - Chunking Helpers
    private func appendToChunkBuffer(_ text: String) {
        if chunkBufferStartTime == nil { chunkBufferStartTime = Date() }
        if !chunkBufferText.isEmpty { chunkBufferText += " " }
        chunkBufferText += text
        
        let elapsed = (chunkBufferStartTime != nil) ? Date().timeIntervalSince(chunkBufferStartTime!) : 0
        if chunkBufferText.count >= chunkMaxChars || elapsed >= chunkMaxSeconds {
            flushChunkBuffer(force: false)
        }
    }
    
    private func flushChunkBuffer(force: Bool) {
        guard let sessionId = currentListenSession else { return }
        let text = chunkBufferText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        
        // NOTE: Removed vector memory storage for listen sessions
        // Listen sessions now use direct transcript context instead of vector memory
        // This prevents duplicate storage and improves performance
        
        // Reset buffer
        chunkBufferText = ""
        chunkBufferStartTime = force ? nil : Date()
    }
    
    // MARK: - Legacy compatibility
    func getLatestTranscript() -> String? {
        return transcripts.last
    }
    
    func getAllTranscripts() -> [String] {
        return transcripts
    }
    
    func clearTranscripts() {
        DispatchQueue.main.async {
            self.transcripts.removeAll()
            self.segments.removeAll()
            self.sessions.removeAll()
            self.currentListenSession = nil
            self.currentListenTranscript = ""
            self.currentSession = nil
            // Note: No need to save sessions when clearing - we're not modifying existing sessions
            print("🗑️ Cleared all transcripts and sessions")
        }
    }
    
    
    // MARK: - Summary Generation
    func generateSummaryForSession(_ sessionId: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let transcript = sessions[sessionIndex].fullTranscript
        guard !transcript.isEmpty else { return }
        
        print("🤖 Generating summary for session: \(sessionId)")
        
        // Limit transcript length to prevent large API calls (keep last 8000 chars)
        let limitedTranscript = transcript.count > 8000 ? String(transcript.suffix(8000)) : transcript
        
        // Use the chat API to generate a summary
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Import ClientAPI through a computed property to avoid circular imports
            let client = ClientAPI.shared
            client.chat(
                message: "Please provide a brief summary of this audio transcript in 1-2 sentences:\n\n\(limitedTranscript)",
                sessionId: sessionId
            ) { [weak self] result in
                switch result {
                case .success(let summary):
                    DispatchQueue.main.async {
                        // Re-find session index to prevent crashes if array was modified
                        guard let self = self,
                              let currentSessionIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) else {
                            print("⚠️ Session not found when updating summary")
                            return
                        }
                        // Update the session with the summary
                        self.sessions[currentSessionIndex].summary = summary
                        self.updateSessionInStorage(self.sessions[currentSessionIndex])
                        print("📝 Generated summary: \(summary)")
                    }
                case .failure(let error):
                    print("❌ Failed to generate summary: \(error)")
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - Insights (highlights, action items, tags)
    func generateInsightsForSession(_ sessionId: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let transcript = sessions[sessionIndex].fullTranscript
        guard !transcript.isEmpty else { return }
        print("🤖 Generating insights for session: \(sessionId)")
        
        // Limit transcript length to prevent large API calls (keep last 8000 chars)
        let limitedTranscript = transcript.count > 8000 ? String(transcript.suffix(8000)) : transcript
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let client = ClientAPI.shared
            // Ask server to return strict JSON
            let instruction = "Extract: 1) 3-6 concise bullet highlights; 2) 2-8 actionable, imperative action items; 3) 3-10 short lowercase tags (kebab-case). Respond ONLY as minified JSON: {\"highlights\":[...],\"action_items\":[...],\"tags\":[...]}."
            let prompt = instruction + "\n\nTranscript:\n" + limitedTranscript
            client.chat(message: prompt, sessionId: sessionId) { [weak self] result in
                defer { continuation.resume() }
                guard let self else { return }
                switch result {
                case .success(let text):
                    // Try to parse JSON from the response text
                    if let data = text.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let hl = obj["highlights"] as? [String] ?? []
                        let ai = obj["action_items"] as? [String] ?? []
                        let tg = obj["tags"] as? [String] ?? []
                        DispatchQueue.main.async {
                            // Re-find session index to prevent crashes if array was modified
                            guard let currentSessionIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) else {
                                print("⚠️ Session not found when updating insights")
                                return
                            }
                            self.sessions[currentSessionIndex].highlights = hl
                            self.sessions[currentSessionIndex].actionItems = ai
                            self.sessions[currentSessionIndex].tags = tg
                            self.updateSessionInStorage(self.sessions[currentSessionIndex])
                            print("📝 Saved insights: H=\(hl.count) A=\(ai.count) T=\(tg.count)")
                        }
                    } else {
                        print("⚠️ Insights not in JSON, skipping parse")
                    }
                case .failure(let error):
                    print("❌ Failed insights generation: \(error)")
                }
            }
        }
    }
    
    // MARK: - Transcript Fetching
    
    private func fetchTranscriptText(sessionId: String) -> String {
        if let session = sessions.first(where: { $0.id == sessionId }) {
            return session.fullTranscript
        }
        return ""
    }
    
    // MARK: - Detailed Notes Generation (Most Important)
    func generateCompleteSessionContent(for sessionId: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) else { 
            print("⚠️ Session not found for content generation: \(sessionId)")
            return 
        }
        
        // Load segments from subcollection before generating content
        let transcript = fetchTranscriptText(sessionId: sessionId)
        guard !transcript.isEmpty else { 
            print("⚠️ Empty transcript for content generation: \(sessionId)")
            return 
        }
        
        print("🤖 Generating complete session content for: \(sessionId) (background task)")
        
        // Get user notes from UserDefaults for this session
        let userNotes = UserDefaults.standard.string(forKey: "ListenPanelNotes") ?? ""
        
        // Limit transcript length to prevent large API calls (keep last 8000 chars)
        let limitedTranscript = transcript.count > 8000 ? String(transcript.suffix(8000)) : transcript
        
        // Use async/await instead of continuation to prevent blocking
        do {
            let client = ClientAPI.shared
            
            // Create comprehensive prompt for ALL content generation (header kept intact; transcript shrinks to fit)
            let header: String = """
            You are an expert meeting analyst. Create detailed, comprehensive notes from this transcript.

            Output MUST be in this EXACT JSON format:
            {
              "title": "Concise session title (5-10 words)",
              "summary": "Comprehensive 3-4 sentence summary covering all major topics",
              "notes_markdown": "Detailed structured notes in markdown format with the following pattern:\n\n## Summary\n- Key point 1 with specific details\n- Key point 2 with examples\n- Key point 3 with decisions made\n\n## [Topic Name]\n- Detailed bullet with specific information\n- Another detailed bullet with context\n- Important quote or decision\n- Technical details or process\n\n## [Next Topic Name]\n- Comprehensive bullet point\n- Specific examples mentioned\n- Analysis or conclusions\n- Action items or next steps\n\nFor EACH major topic discussed, create a section with 4-8 detailed bullets. Include:\n- Specific examples and quotes\n- Decisions made and reasoning\n- Technical details discussed\n- Context and background information\n- Action items and next steps\n- Key insights and analysis"
            }
            
            CRITICAL REQUIREMENTS:
            - Be extremely detailed and comprehensive
            - Each bullet point should be substantial (20-50 words)
            - Include specific quotes and examples from the transcript
            - Capture nuance and depth of discussions
            - Output valid JSON only, no other text
            """
            
            let notesBlock: String = userNotes.isEmpty ? "" : "\n\n[User Notes from Session]\n\(userNotes)\n"
            
            // Compose with dynamic transcript budget: server truncates to ~6000 chars, reserve margin
            let suffix = "\n\n[Session Transcript]\n"
            let footer = "\n\nRespond with STRICT JSON only, no commentary."
            let fixed = header + notesBlock + suffix
            let maxTotal = 5900 // stay below server 6000 truncation
            let availableForTranscript = max(0, maxTotal - (fixed.count + footer.count))
            let sizedTranscript: String = {
                if limitedTranscript.count <= availableForTranscript { return limitedTranscript }
                // Keep the most recent portion
                return String(limitedTranscript.suffix(availableForTranscript))
            }()
            let prompt = fixed + sizedTranscript + footer
            
            print("📤 Sending content generation request for session: \(sessionId)")
            print("📝 Prompt length: \(prompt.count) chars, Transcript used: \(sizedTranscript.count)/\(limitedTranscript.count) chars")
            
            // Use the chat endpoint for detailed note generation
            // Skip memory extraction for transcript content generation
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                client.chatWithoutMemoryExtraction(message: prompt, sessionId: sessionId) { [weak self] result in
                    switch result {
                    case .success(let response):
                        print("📥 Received response for session \(sessionId): \(response.prefix(200))...")
                        DispatchQueue.main.async {
                            guard let self = self else { 
                                print("⚠️ Self is nil in content generation callback")
                                continuation.resume()
                                return 
                            }
                            self.processCompleteSessionContent(response: response, sessionId: sessionId)
                            print("✅ Generated complete session content for: \(sessionId)")
                        }
                    case .failure(let error):
                        print("❌ Failed to generate complete session content for \(sessionId): \(error)")
                    }
                    continuation.resume()
                }
            }
        } catch {
            print("❌ Error in content generation for \(sessionId): \(error)")
        }
    }
    
    private func processCompleteSessionContent(response: String, sessionId: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) else { 
            print("❌ Session not found for content processing: \(sessionId)")
            return 
        }
        
        print("🔄 Processing content for session: \(sessionId)")
        print("📥 Response length: \(response.count) chars")
        
        // Parse JSON response
        guard let data = response.data(using: .utf8) else {
            print("❌ Failed to convert response to data")
            return
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let content = json as? [String: Any] else {
                print("❌ Failed to parse JSON response")
                return
            }
            
            print("📋 Parsed JSON keys: \(Array(content.keys))")
            
            // Title (if provided) — persist once
            if let autoTitle = content["title"] as? String, !autoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessions[sessionIndex].title = autoTitle
                print("📝 Updated title: \(autoTitle)")
            } else if sessions[sessionIndex].title == nil || sessions[sessionIndex].title!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessions[sessionIndex].title = sessions[sessionIndex].generatedTitle
                print("📝 Using generated title: \(sessions[sessionIndex].generatedTitle)")
            }

            // Summary (mandatory in prompt) — store if present
            if let summary = content["summary"] as? String, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessions[sessionIndex].summary = summary
                print("📝 Updated summary: \(summary.prefix(100))...")
            } else {
                print("⚠️ No summary found in response")
            }

            // Store free-form topic-based notes (ensure Summary appears as first section)
            if var notes = content["notes_markdown"] as? String {
                print("📝 Found notes_markdown field with \(notes.count) chars")
                
                // Detect an existing "## Summary" heading (start of string or newline)
                let pattern = "(^|\\n)##\\s+Summary(\\s|$)"
                let hasSummaryHeading = notes.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                if let summary = sessions[sessionIndex].summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !hasSummaryHeading {
                    let prefixed = "## Summary\n\(summary)\n\n" + notes
                    notes = prefixed
                    print("📝 Added summary heading to notes")
                }
                // Store notes in the session
                sessions[sessionIndex].notes = notes
                print("📝 Stored detailed notes: \(notes.prefix(100))...")
            } else {
                print("⚠️ No notes_markdown field found in response")
            }
            
            // Mark session as complete and update in storage
            if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[sessionIndex].isComplete = true
                updateSessionInStorage(sessions[sessionIndex])
                print("💾 Updated session in storage and marked as complete")
            }
            
            print("✅ Successfully processed and saved complete session content for: \(sessionId)")
            
        } catch {
            print("❌ Failed to parse JSON response: \(error)")
            print("📥 Raw response: \(response)")
        }
    }
    
    func generateDetailedNotesForSession(_ sessionId: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let transcript = sessions[sessionIndex].fullTranscript
        guard !transcript.isEmpty else { return }
        
        print("🤖 Generating detailed notes for session: \(sessionId)")
        
        // Mark session as generating notes
        DispatchQueue.main.async {
            self.generatingNotesForSessions.insert(sessionId)
        }
        
        // Get user notes from UserDefaults for this session
        let userNotes = UserDefaults.standard.string(forKey: "ListenPanelNotes") ?? ""
        
        // Limit transcript length to prevent large API calls (keep last 8000 chars)
        let limitedTranscript = transcript.count > 8000 ? String(transcript.suffix(8000)) : transcript
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let client = ClientAPI.shared
            
            // Create comprehensive prompt for detailed notes
            var prompt = """
            You are an expert note-taker and meeting analyst. Create comprehensive, detailed notes that capture EVERYTHING important from this session.
            
            Guidelines:
            - Write in clear, professional language with proper paragraphs
            - Include ALL key discussions, decisions, outcomes, and insights
            - Focus on narrative content and story flow
            - Use paragraphs for readability, avoid bullet points
            - Be extremely thorough and detailed - capture the full depth of each discussion
            - Include specific examples, quotes, and technical details mentioned
            - Create a flowing narrative that tells the complete story of the session
            - Cover every major topic discussed with comprehensive detail
            - Include context, background information, and reasoning behind decisions
            - Do NOT include structured lists, highlights, or action items (these are handled separately)
            
            """
            
            if !userNotes.isEmpty {
                prompt += """
                
                [User Notes from Session]
                \(userNotes)
                
                """
            }
            
            prompt += """
            
            [Session Transcript]
            \(limitedTranscript)
            
            Please create detailed notes that combine insights from both the user notes and transcript above. This should be the most comprehensive analysis of the session in paragraph form, telling the complete story of what happened. Be extremely detailed and thorough - capture every important discussion point, decision, insight, and technical detail mentioned in the session.
            """
            
            client.chat(message: prompt, sessionId: sessionId) { [weak self] result in
                switch result {
                case .success(let detailedNotes):
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Store detailed notes in the session
                        if let sessionIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) {
                            self.sessions[sessionIndex].notes = detailedNotes
                            // Update session in local storage
                            self.updateSessionInStorage(self.sessions[sessionIndex])
                            print("📝 Generated and stored detailed notes: \(detailedNotes.prefix(100))...")
                        }
                        // Remove from generating set
                        self.generatingNotesForSessions.remove(sessionId)
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        // Remove from generating set even on failure
                        self?.generatingNotesForSessions.remove(sessionId)
                    }
                    print("❌ Failed to generate detailed notes: \(error)")
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - DeepgramSTTDelegate
    
    func didReceiveTranscription(_ text: String, isFinal: Bool, confidence: Float, source: DeepgramSTT.SourceType) {
        logger.info("📝 Received transcription: '\(text)' (final: \(isFinal), confidence: \(confidence))")
        
        DispatchQueue.main.async {
            if isFinal {
                // Add final transcription to session
                let mapped: TranscriptSegment.TranscriptSource = (source == .microphone) ? .microphone : .system
                self.addListenTranscriptSegment(text, isPartial: false, source: mapped)
                self.logger.info("✅ Added final transcription segment")
                
                // Clear live transcript indicators since it's now finalized
                self.partialUpdateTimer?.invalidate()
                self.partialUpdateTimer = nil
                self.livePartialTranscript = ""
                self.isReceivingPartialTranscript = false
            } else {
                // Update live transcript for partial results with debouncing
                self.updatePartialTranscript(text, confidence: confidence)
            }
        }
    }
    
    private func updatePartialTranscript(_ text: String, confidence: Float) {
        // Cancel previous timer
        partialUpdateTimer?.invalidate()
        
        // Set new timer for debounced update
        partialUpdateTimer = Timer.scheduledTimer(withTimeInterval: partialUpdateDebounceInterval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let formattedText = self.formatPartialTranscript(text, confidence: confidence)
                self.livePartialTranscript = formattedText
                self.isReceivingPartialTranscript = true
                self.logger.debug("🔄 Updated live transcript: \(formattedText)")
            }
        }
    }
    
    private func formatPartialTranscript(_ text: String, confidence: Float) -> String {
        // Simple text formatting - no emoji indicators for cleaner look
        return text
    }

    // MARK: - Title Generation (internal)
    private func generateDeterministicTitle(from session: ListenSession) -> String {
        // Reuse the extension logic via a minimal wrapper to keep behavior identical
        return session.generatedTitle
    }

    /// Ensure a title is generated and saved once for a session
    func generateTitleIfNeeded(for sessionId: String) async {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let current = sessions[idx]
        if let existing = current.title, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let title = generateDeterministicTitle(from: current)
        DispatchQueue.main.async {
            self.sessions[idx].title = title
            self.updateSessionInStorage(self.sessions[idx])
        }
    }
    
    func didReceiveError(_ error: Error, source: DeepgramSTT.SourceType) {
        logger.error("❌ Deepgram STT error: \(error)")
    }
    
    func didConnect(source: DeepgramSTT.SourceType) {
        logger.info("✅ Deepgram STT connected")
    }
    
    func didDisconnect(source: DeepgramSTT.SourceType) {
        logger.info("🔌 Deepgram STT disconnected")
    }
}

// MARK: - Codable Support for Persistence

struct ListenSessionData: Codable {
    let id: String
    let startTime: Date
    let endTime: Date?
    let segments: [TranscriptSegmentData]
    let summary: String?
    let title: String?
    let highlights: [String]
    let actionItems: [String]
    let tags: [String]
    let notes: String?
    let isComplete: Bool
    
    func toListenSession() -> ListenSession {
        return ListenSession(
            data: self
        )
    }
    
    init(from session: ListenSession) {
        self.id = session.id
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.segments = session.segments.map { TranscriptSegmentData(from: $0) }
        self.summary = session.summary
        self.title = session.title
        self.highlights = session.highlights
        self.actionItems = session.actionItems
        self.tags = session.tags
        self.notes = session.notes
        self.isComplete = session.isComplete
    }
}

extension ListenSession {
    init(data: ListenSessionData) {
        self.id = data.id
        self.startTime = data.startTime
        self.endTime = data.endTime
        self.segments = data.segments.map { $0.toTranscriptSegment() }
        self.summary = data.summary
        self.title = data.title
        self.highlights = data.highlights
        self.actionItems = data.actionItems
        self.tags = data.tags
        self.notes = data.notes
        self.isComplete = data.isComplete
    }
}

// MARK: - Title Generation (ListenSession extension)
extension ListenSession {
    var generatedTitle: String {
        if let storedTitle = title, !storedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedTitle
        }
        if let summary = summary, !summary.isEmpty {
            return extractTitleFromContent(summary)
        }
        if !fullTranscript.isEmpty {
            return extractTitleFromContent(fullTranscript)
        }
        let userNotes = UserDefaults.standard.string(forKey: "ListenPanelNotes") ?? ""
        if !userNotes.isEmpty { return extractTitleFromContent(userNotes) }
        let formatter = DateFormatter(); formatter.dateFormat = "MMM d, h:mm a"
        return "Session " + formatter.string(from: startTime)
    }
}

// Keep helpers file-local
private func extractTitleFromContent(_ content: String) -> String {
    let words = content.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return "" }
    let meetingType = determineMeetingType(from: content)
    let keyWords = extractKeyTopics(from: content)
    if meetingType != "Discussion" {
        if keyWords.count >= 2 { return "\(meetingType) \(keyWords.prefix(3).joined(separator: " "))" }
        return meetingType
    }
    if keyWords.count >= 2 {
        let topics = keyWords.prefix(5)
        if meetingType != "Discussion" { return "\(meetingType) \(topics.joined(separator: " "))" }
        else { return topics.joined(separator: " ") }
    }
    let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
    if let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) {
        let words = firstSentence.split(separator: " ").map(String.init)
        let meaningfulWords = words.filter { word in
            let lower = word.lowercased()
            return lower.count > 3 && !["the","and","with","this","that","from","they","have","been","will","were","said","each","which","their","said","would","there","could","other","about","discussed","talked","mentioned","going","think","know","want","need","like","good","great","really","actually"].contains(lower)
        }
        if meaningfulWords.count >= 2 { return meaningfulWords.prefix(7).joined(separator: " ") }
        else if words.count > 2 { return words.prefix(6).joined(separator: " ") }
    }
    return ""
}

private func determineMeetingType(from content: String) -> String {
    let lower = content.lowercased()
    if lower.contains("standup") || lower.contains("daily standup") { return "Daily Standup" }
    else if lower.contains("retrospective") || lower.contains("retro") { return "Retrospective" }
    else if lower.contains("sprint planning") { return "Sprint Planning" }
    else if lower.contains("demo") || lower.contains("demonstration") { return "Demo" }
    else if lower.contains("interview") { return "Interview" }
    else if lower.contains("presentation") { return "Presentation" }
    else if lower.contains("workshop") { return "Workshop" }
    else if lower.contains("training") { return "Training" }
    else if lower.contains("review") { return "Review" }
    else if lower.contains("planning") { return "Planning" }
    else if lower.contains("brainstorming") { return "Brainstorming" }
    else if lower.contains("one on one") || lower.contains("1:1") { return "One-on-One" }
    else if lower.contains("team meeting") { return "Team Meeting" }
    else if lower.contains("client meeting") { return "Client Meeting" }
    else if lower.contains("project") { return "Project" }
    else if lower.contains("call") { return "Call" }
    else if lower.contains("meeting") { return "Meeting" }
    return "Discussion"
}

private func extractKeyTopics(from content: String) -> [String] {
    let words = content.lowercased().components(separatedBy: .whitespacesAndNewlines)
    let stopWords = Set([
        "the","and","with","this","that","from","they","have","been","will","were","said",
        "each","which","their","said","would","there","could","other","about","discussed",
        "talked","mentioned","like","just","also","very","really","some","more","most",
        "much","many","all","any","can","should","would","could","might","may","must",
        "going","think","know","want","need","good","great","actually","right","well",
        "now","here","there","back","over","under","through","during","before","after"
    ])
    let meaningful = words.filter { w in
        w.count > 3 && !stopWords.contains(w) && !w.isEmpty && !w.hasPrefix("http") && !w.contains("@") && w.rangeOfCharacter(from: .letters) != nil
    }
    let wordCounts = Dictionary(grouping: meaningful, by: { $0 })
        .mapValues { $0.count }
        .sorted { (a, b) in
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }
    return wordCounts.prefix(5).map { $0.key.capitalized }
}

struct TranscriptSegmentData: Codable {
    let id: String
    let text: String
    let timestamp: Date
    let type: String
    let sessionId: String?
    let confidence: Float
    let source: String?
    
    func toTranscriptSegment() -> TranscriptSegment {
        let segmentType: TranscriptSegment.TranscriptType
        switch type {
        case "server": segmentType = .server
        case "listen": segmentType = .listen
        case "partial": segmentType = .partial
        default: segmentType = .listen
        }
        
        return TranscriptSegment(
            text: text,
            timestamp: timestamp,
            type: segmentType,
            sessionId: sessionId,
            confidence: confidence,
            source: (source == "microphone") ? .microphone : .system
        )
    }
    
    init(from segment: TranscriptSegment) {
        self.id = segment.id.uuidString
        self.text = segment.text
        self.timestamp = segment.timestamp
        self.sessionId = segment.sessionId
        self.confidence = segment.confidence
        self.source = segment.source.rawValue
        
        switch segment.type {
        case .server: self.type = "server"
        case .listen: self.type = "listen"
        case .partial: self.type = "partial"
        }
    }
}
