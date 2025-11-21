import Foundation
import CryptoKit

// MARK: - Enhanced Memory Models with Vector Support

enum MemoryType: String, Codable {
    case personal = "personal"
    case preference = "preference"
    case professional = "professional"
    case goal = "goal"
    case instruction = "instruction"
    case knowledge = "knowledge"
    case relationship = "relationship"
    case event = "event"
}

enum MemorySource: String, Codable {
    case conversation = "conversation"
    case screenshot = "screenshot"
    case explicit = "explicit"
    case inferred = "inferred"
}

struct VectorMemory: Codable {
    let id: String
    let userId: String
    let type: MemoryType
    let content: String
    let summary: String
    let keywords: [String]
    let embedding: [Double] // Vector embedding for semantic search
    let importance: Double
    let confidence: Double
    let source: MemorySource
    let context: MemoryContext
    let createdAt: Date
    let lastAccessedAt: Date
    let accessCount: Int
    let decayFactor: Double // For memory importance decay over time
    let isActive: Bool
    // New: fast exact/small-change dedup
    let contentHash: String?
}

extension VectorMemory {
    func updating(
        content: String? = nil,
        summary: String? = nil,
        keywords: [String]? = nil,
        embedding: [Double]? = nil,
        importance: Double? = nil,
        confidence: Double? = nil,
        source: MemorySource? = nil,
        context: MemoryContext? = nil,
        lastAccessedAt: Date? = nil,
        accessCount: Int? = nil,
        decayFactor: Double? = nil,
        isActive: Bool? = nil
    ) -> VectorMemory {
        VectorMemory(
            id: id,
            userId: userId,
            type: type,
            content: content ?? self.content,
            summary: summary ?? self.summary,
            keywords: keywords ?? self.keywords,
            embedding: embedding ?? self.embedding,
            importance: importance ?? self.importance,
            confidence: confidence ?? self.confidence,
            source: source ?? self.source,
            context: context ?? self.context,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt ?? self.lastAccessedAt,
            accessCount: accessCount ?? self.accessCount,
            decayFactor: decayFactor ?? self.decayFactor,
            isActive: isActive ?? self.isActive,
            contentHash: self.contentHash
        )
    }
}

// MARK: - Message and Session Models

enum MessageType: String, Codable {
    case text = "text"
    case screenshot = "screenshot"
    case analysis = "analysis"
}

struct StoredChatMessage: Codable {
    let id: String
    let userId: String
    let sessionId: String
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
    let type: MessageType
    let tokens: Int? // Token count for context management
}

struct ChatSession: Codable {
    let id: String
    let userId: String
    let title: String // Auto-generated session title
    let summary: String // Condensed summary of the conversation
    let startedAt: Date
    let lastActivityAt: Date
    let messageCount: Int
    let totalTokens: Int // For context window management
    let keyTopics: [String] // Main topics discussed
    let isActive: Bool
    let memoryCount: Int // How many memories created from this session
}

struct MemoryContext: Codable {
    let sessionId: String
    let messageId: String?
    let timestamp: Date
    let conversationTopic: String?
    let relatedMemories: [String] // IDs of related memories
}

struct UserProfile: Codable {
    let userId: String
    let preferences: UserPreferences
    let memorySettings: MemorySettings
    let createdAt: Date
    let updatedAt: Date
}

struct UserPreferences: Codable {
    let communicationStyle: String? // formal, casual, technical
    let responseLength: String? // brief, detailed, varies
    let interests: [String]
    let timezone: String?
    let language: String?
}

struct MemorySettings: Codable {
    let isEnabled: Bool
    let autoExtraction: Bool
    let retentionDays: Int? // How long to keep memories (nil = forever)
    let maxMemories: Int? // Maximum number of memories to store
    let sensitivityLevel: String // what kind of info to remember
}

struct ExtractedFact: Codable {
    let text: String
    let summary: String
    let kind: String
    let importance: Double
}

struct MemorySearchResult {
    let memory: VectorMemory
    let relevanceScore: Double // Combined semantic + importance + recency score
    let semanticSimilarity: Double
    let importanceBoost: Double
    let recencyBoost: Double
}

// MARK: - Vector Memory Manager

@MainActor
class VectorMemoryManager: ObservableObject {
    static let shared = VectorMemoryManager()
    
    private let memoryStorage = VectorMemoryStorageService.shared
    private let embeddingCache = NSCache<NSString, NSArray>()
    private let maxContextTokens = 2000
    private let maxRetrievedMemories = 15
    
    @Published var isProcessingMemory = false
    @Published var currentSessionId: String?
    
    private init() {
        setupEmbeddingCache()
        // Listen for session changes from SessionManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidChange),
            name: .sessionDidChange,
            object: nil
        )
    }
    
    private func setupEmbeddingCache() {
        embeddingCache.countLimit = 100 // Cache up to 100 embeddings
        embeddingCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    @objc private func sessionDidChange(_ notification: Notification) {
        if let newSessionId = notification.object as? String {
            DispatchQueue.main.async {
                self.currentSessionId = newSessionId
                print("🔄 VectorMemoryManager: Session ID updated to: \(newSessionId)")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Current User
    
    private var currentUserId: String {
        APIKeyManager.shared.localUserId
    }
    
    // MARK: - Enhanced Memory Storage with Embeddings
    
    func storeMemoryWithEmbedding(content: String, type: MemoryType, source: MemorySource, importance: Double = 0.7) async {
        let userId = currentUserId
        
        // Normalize content: remove chat role prefixes like "User:" / "Assistant:"
        let normalized = content.replacingOccurrences(of: "^\\s*(user|assistant)\\s*:\\s*", with: "", options: [.regularExpression, .caseInsensitive])

        // Guard against low-signal/greeting-like content
        if isLowSignalMemory(normalized) {
            print("🚫 Skipping low-signal memory: \(normalized.prefix(60))")
            return
        }

        print("🔄 storeMemoryWithEmbedding: Starting storage for user ID: \(userId)")
        print("   - Content: \(normalized.prefix(100))...")
        print("   - Type: \(type.rawValue)")
        
        isProcessingMemory = true
        defer { isProcessingMemory = false }
        
        // QUICK DEDUP: content hash match (exact/small punctuation changes)
        if await existsByContentHash(userId: userId, content: normalized) {
            print("🛑 Duplicate by content hash — skipping store")
            return
        }

        // SEMANTIC DEDUP before embedding generation cost (use lightweight keyword+type search)
        if let similarMemory = await findSimilarMemory(userId: userId, content: normalized, threshold: 0.88) {
            // Merge into existing memory (upsert)
            await mergeIntoExistingMemory(existing: similarMemory, newContent: normalized, importance: importance)
            print("📝 Merged into similar existing memory")
            return
        }
        
        let keywords = extractEnhancedKeywords(from: normalized)
        let summary = generateSummary(from: normalized)
        
        // Intelligently determine memory type if not specified
        let finalType = type == .knowledge ? detectMemoryType(from: normalized) : type
        
        // Generate embedding for the content
        guard let embedding = await generateEmbedding(for: normalized) else {
            print("❌ Failed to generate embedding for content, storing without embedding")
            await storeMemoryWithoutEmbedding(content: normalized, type: finalType, source: source, importance: importance)
            return
        }
        
        let memory = VectorMemory(
            id: UUID().uuidString,
            userId: userId,
            type: finalType,
            content: normalized,
            summary: summary,
            keywords: keywords,
            embedding: embedding,
            importance: importance,
            confidence: 0.8,
            source: source,
            context: MemoryContext(
                sessionId: getCurrentSessionId(),
                messageId: nil,
                timestamp: Date(),
                conversationTopic: nil,
                relatedMemories: []
            ),
            createdAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 0,
            decayFactor: 1.0,
            isActive: true,
            contentHash: sha256(normalized)
        )
        
        await storeVectorMemory(memory)
    }
    
    private func storeMemoryWithoutEmbedding(content: String, type: MemoryType, source: MemorySource, importance: Double) async {
        let userId = currentUserId
        
        print("💾 Storing memory without embedding for user ID: \(userId)")
        
        let keywords = extractEnhancedKeywords(from: content)
        let summary = generateSummary(from: content)
        
        let memory = VectorMemory(
            id: UUID().uuidString,
            userId: userId,
            type: type,
            content: content,
            summary: summary,
            keywords: keywords,
            embedding: [], // Empty embedding array
            importance: importance,
            confidence: 0.6, // Lower confidence without embedding
            source: source,
            context: MemoryContext(
                sessionId: getCurrentSessionId(),
                messageId: nil,
                timestamp: Date(),
                conversationTopic: nil,
                relatedMemories: []
            ),
            createdAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 0,
            decayFactor: 1.0,
            isActive: true,
            contentHash: sha256(content)
        )
        
        await storeVectorMemory(memory)
    }
    
    private func storeVectorMemory(_ memory: VectorMemory) async {
        do {
            try await memoryStorage.saveMemory(memory)
            print("✅ Successfully stored vector memory locally: \(memory.summary) (ID: \(memory.id))")
        } catch {
            print("❌ Failed to store vector memory locally: \(error)")
        }
    }

    private func mergeIntoExistingMemory(existing: VectorMemory, newContent: String, importance: Double) async {
        let isReplacement = detectReplacement(newContent)
        let newSummary = isReplacement ? generateSummary(from: newContent) : existing.summary
        let mergedKeywordSet = Set(existing.keywords + extractEnhancedKeywords(from: newContent))
        let mergedKeywords: [String] = Array(mergedKeywordSet.prefix(20))
        let newImportance = max(existing.importance, min(1.0, importance + 0.05))
        let updatedContent = existing.content.contains(newContent) ? existing.content : existing.content + "\n" + newContent
        
        let updatedMemory = existing.updating(
            content: updatedContent,
            summary: newSummary,
            keywords: mergedKeywords,
            importance: newImportance,
            lastAccessedAt: Date(),
            accessCount: existing.accessCount + 1
        )
        
        do {
            try await memoryStorage.updateMemory(updatedMemory)
        } catch {
            print("❌ Failed to merge memory locally: \(error)")
        }
    }

    private func detectReplacement(_ content: String) -> Bool {
        let patterns = [
            "actually", "correction", "i meant", "not anymore", "used to",
            "changed my mind", "now i ", "instead", "rather"
        ]
        let lower = content.lowercased()
        return patterns.contains { lower.contains($0) }
    }
    
    // MARK: - OpenAI Embedding Generation
    
    private func generateEmbedding(for text: String) async -> [Double]? {
        // Check cache first
        let cacheKey = NSString(string: sha256(text))
        if let cachedEmbedding = embeddingCache.object(forKey: cacheKey) as? [Double] {
            return cachedEmbedding
        }
        
        // Call OpenAI embedding API
        guard let url = URL(string: "\(AppConfig.serverBaseURL)/api/embedding") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
            let body: [String: Any] = [
                "text": text,
                "userId": currentUserId
            ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let embedding = response?["embedding"] as? [Double] else {
                print("⚠️ No embedding in API response")
                return nil
            }
            
            print("🔢 Embedding dimensions from server: \(embedding.count)")
            // optionally assert same dim
            if embedding.count < 128 {
               print("⚠️ Unexpected embedding dimensionality: \(embedding.count)")
            }
            
            // Cache the embedding
            embeddingCache.setObject(embedding as NSArray, forKey: cacheKey)
            
            print("🔢 Generated embedding with \(embedding.count) dimensions")
            return embedding
            
        } catch {
            print("❌ Embedding generation error: \(error)")
            return nil
        }
    }
    
    // MARK: - Semantic Memory Retrieval
    
    func getRelevantMemoriesWithContext(for query: String, sessionId: String? = nil) async -> String {
        let userId = currentUserId
        
        let actualSessionId = sessionId ?? getCurrentSessionId()
        
        // Generate embedding for the query
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            print("❌ Failed to generate query embedding")
            return await getFallbackContext(query: query, sessionId: actualSessionId)
        }
        
        // Retrieve semantically similar memories
        let relevantMemories = await searchSimilarMemories(
            userId: userId,
            queryEmbedding: queryEmbedding,
            query: query
        )
        
        // Get session-specific conversation context
        let sessionContext = await getSessionConversationContext(sessionId: actualSessionId)
        
        // Get live transcription context
        let liveTranscriptionContext = await getLiveTranscriptionContext(sessionId: actualSessionId)
        
        // Build comprehensive context with memories, session context, and live transcriptions
        return buildEnhancedContextFromMemories(
            memories: relevantMemories, 
            sessionContext: sessionContext, 
            liveTranscriptionContext: liveTranscriptionContext,
            query: query,
            sessionId: actualSessionId
        )
    }
    
    private func searchSimilarMemories(userId: String, queryEmbedding: [Double], query: String) async -> [MemorySearchResult] {
        let activeMemories = await memoryStorage.activeMemories(for: userId, limit: 200)
        var searchResults: [MemorySearchResult] = []
        
        for memory in activeMemories {
            let semantic = cosineSimilarity(queryEmbedding, memory.embedding)
            let importanceBoost = memory.importance * 0.3
            let daysSinceCreated = Date().timeIntervalSince(memory.createdAt) / (24 * 60 * 60)
            let recencyBoost = max(0, 0.15 * exp(-daysSinceCreated / 30.0))
            let accessBoost = min(0.1, Double(memory.accessCount) * 0.02)
            let decayBoost = memory.importance * memory.decayFactor * 0.05
            let keywordMatch = memory.keywords.contains { query.lowercased().contains($0.lowercased()) }
            let exactKeywordBoost = keywordMatch ? 0.2 : 0.0
            let fuzzyKeywordBoost = calculateFuzzyKeywordMatch(query: query, keywords: memory.keywords) * 0.1
            let typeBoost = calculateTypeRelevance(memoryType: memory.type, query: query) * 0.1
            
            let finalScore = semantic + importanceBoost + recencyBoost + accessBoost + decayBoost + exactKeywordBoost + fuzzyKeywordBoost + typeBoost
            
            if semantic > 0.3 || keywordMatch {
                let result = MemorySearchResult(
                    memory: memory,
                    relevanceScore: finalScore,
                    semanticSimilarity: semantic,
                    importanceBoost: importanceBoost,
                    recencyBoost: recencyBoost
                )
                searchResults.append(result)
                
                Task {
                    await updateMemoryAccess(memoryId: memory.id)
                }
            }
        }
        
        let sortedResults = searchResults
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(maxRetrievedMemories)
            .map { $0 }
        
        let topDebug = sortedResults.prefix(5)
        for r in topDebug {
            print("DBG memory \(r.memory.id) sem:\(String(format: "%.3f", r.semanticSimilarity)) final:\(String(format: "%.3f", r.relevanceScore)) tags:\(r.memory.keywords)")
        }
        
        return Array(sortedResults)
    }
    
    // MARK: - Session Context Management
    
    private func getSessionConversationContext(sessionId: String) async -> String {
        let recentMessages = await getRecentMessages(sessionId: sessionId, limit: 10)
        
        if recentMessages.isEmpty {
            return ""
        }
        
        var contextLines: [String] = []
        for message in recentMessages.reversed() { // Show oldest first
            let role = message.role == "user" ? "User" : "Assistant"
            let content = String(message.content.prefix(200)) // Limit message length
            contextLines.append("\(role): \(content)")
        }
        
        return contextLines.joined(separator: "\n")
    }
    
    private func getLiveTranscriptionContext(sessionId: String?) async -> String {
        // Import SessionTranscriptStore to access live transcriptions
        let transcriptStore = SessionTranscriptStore.shared
        
        // Check if there's an active listen session
        guard let currentSessionId = transcriptStore.currentListenSession else {
            return ""
        }
        
        // Get recent transcript segments (last 10 minutes)
        let tenMinutesAgo = Date().addingTimeInterval(-10 * 60)
        let recentSegments = transcriptStore.displaySegments.filter { segment in
            segment.sessionId == currentSessionId && 
            segment.timestamp >= tenMinutesAgo &&
            segment.type == .listen // Only completed segments, not partial
        }
        
        if recentSegments.isEmpty {
            // Check if there's any live partial transcript
            if !transcriptStore.livePartialTranscript.isEmpty {
                return "[Live Meeting Context: Currently transcribing: \"\(transcriptStore.livePartialTranscript)\"]"
            }
            return ""
        }
        
        // Extract key information from recent transcriptions
        let recentTranscript = recentSegments.map { $0.text }.joined(separator: " ")
        
        // Smart filtering and summarization
        let keyTopics = extractKeyTopics(from: recentTranscript)
        let deadlines = extractDeadlines(from: recentTranscript)
        let decisions = extractDecisions(from: recentTranscript)
        
        var contextLines: [String] = []
        contextLines.append("[Live Meeting Context - Last 10 minutes:]")
        
        if !keyTopics.isEmpty {
            contextLines.append("Key Topics: \(keyTopics.joined(separator: ", "))")
        }
        
        if !deadlines.isEmpty {
            contextLines.append("Deadlines Mentioned: \(deadlines.joined(separator: ", "))")
        }
        
        if !decisions.isEmpty {
            contextLines.append("Decisions Made: \(decisions.joined(separator: ", "))")
        }
        
        // Add recent transcript summary (truncated)
        let summary = String(recentTranscript.prefix(500))
        contextLines.append("Recent Discussion: \(summary)")
        
        return contextLines.joined(separator: "\n")
    }
    
    // MARK: - Transcription Analysis Helpers
    
    private func extractKeyTopics(from transcript: String) -> [String] {
        let words = transcript.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let topicKeywords = [
            "project", "meeting", "deadline", "budget", "team", "client", "proposal",
            "feature", "bug", "release", "sprint", "milestone", "review", "feedback",
            "presentation", "demo", "strategy", "planning", "roadmap", "goals"
        ]
        
        var topics: Set<String> = []
        for keyword in topicKeywords {
            if words.contains(keyword) {
                topics.insert(keyword.capitalized)
            }
        }
        
        return Array(topics).prefix(5).map { $0 } // Limit to 5 topics
    }
    
    private func extractDeadlines(from transcript: String) -> [String] {
        let deadlinePatterns = [
            "deadline.*?(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})",
            "due.*?(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})",
            "by.*?(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})",
            "march \\d{1,2}", "april \\d{1,2}", "may \\d{1,2}",
            "june \\d{1,2}", "july \\d{1,2}", "august \\d{1,2}",
            "september \\d{1,2}", "october \\d{1,2}", "november \\d{1,2}", "december \\d{1,2}"
        ]
        
        var deadlines: Set<String> = []
        let lowerTranscript = transcript.lowercased()
        
        for pattern in deadlinePatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: lowerTranscript.count)
            let matches = regex?.matches(in: lowerTranscript, options: [], range: range) ?? []
            
            for match in matches {
                if let range = Range(match.range, in: lowerTranscript) {
                    let deadline = String(lowerTranscript[range])
                    deadlines.insert(deadline.capitalized)
                }
            }
        }
        
        return Array(deadlines).prefix(3).map { $0 } // Limit to 3 deadlines
    }
    
    private func extractDecisions(from transcript: String) -> [String] {
        let decisionKeywords = [
            "decided", "agreed", "approved", "rejected", "chosen", "selected",
            "will do", "going to", "plan to", "committed to", "agreement"
        ]
        
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var decisions: [String] = []
        
        for sentence in sentences {
            let lowerSentence = sentence.lowercased()
            for keyword in decisionKeywords {
                if lowerSentence.contains(keyword) {
                    let decision = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if decision.count > 10 && decision.count < 100 {
                        decisions.append(decision)
                    }
                }
            }
        }
        
        return Array(decisions).prefix(3).map { $0 } // Limit to 3 decisions
    }
    
    private func buildEnhancedContextFromMemories(
        memories: [MemorySearchResult], 
        sessionContext: String, 
        liveTranscriptionContext: String,
        query: String,
        sessionId: String
    ) -> String {
        var context = ""
        var usedTokens = 0
        let maxTokens = maxContextTokens
        
        // Token allocation strategy:
        // 20% for user profile, 30% for memories, 50% for conversation
        let profileTokenLimit = maxTokens / 5
        let memoryTokenLimit = (maxTokens * 30) / 100
        let conversationTokenLimit = (maxTokens * 50) / 100
        
        // 1. Build comprehensive user profile (ChatGPT style)
        let userProfile = buildUserProfile(from: memories, tokenLimit: profileTokenLimit)
        if !userProfile.isEmpty {
            context += userProfile
            usedTokens += userProfile.count / 4
        }
        
        // 2. Add most relevant memories with better scoring
        let relevantMemories = selectRelevantMemories(memories: memories, query: query, tokenLimit: memoryTokenLimit)
        if !relevantMemories.isEmpty {
            context += "Relevant Context:\n\(relevantMemories)\n"
            usedTokens += relevantMemories.count / 4
        }
        
        // 3. Add optimized conversation context
        let optimizedConversation = optimizeConversationContext(sessionContext, tokenLimit: conversationTokenLimit)
        if !optimizedConversation.isEmpty {
            context += "Recent Conversation:\n\(optimizedConversation)\n"
            usedTokens += optimizedConversation.count / 4
        }
        
        // 4. Add live transcription context (highest priority for real-time meetings)
        if !liveTranscriptionContext.isEmpty {
            context += "\(liveTranscriptionContext)\n"
            usedTokens += liveTranscriptionContext.count / 4
        }
        
        print("🧠 Built enhanced context: \(usedTokens) tokens, \(memories.count) memories, session: \(sessionId), live transcription: \(!liveTranscriptionContext.isEmpty)")
        return context
    }
    
    private func buildUserProfile(from memories: [MemorySearchResult], tokenLimit: Int) -> String {
        let personalMemories = memories.filter { 
            $0.memory.type == .personal || $0.memory.type == .preference 
        }.sorted { $0.memory.importance > $1.memory.importance }
        
        if personalMemories.isEmpty { return "" }
        
        var profile = "User Profile:\n"
        var usedTokens = "User Profile:\n".count / 4
        
        // Group by type for better organization
        let personal = personalMemories.filter { $0.memory.type == .personal }
        let preferences = personalMemories.filter { $0.memory.type == .preference }
        
        // Add personal info first
        for memory in personal.prefix(3) {
            let memoryText = "- \(memory.memory.summary)\n"
            let tokens = memoryText.count / 4
            if usedTokens + tokens <= tokenLimit {
                profile += memoryText
                usedTokens += tokens
            } else { break }
        }
        
        // Add preferences
        if usedTokens < tokenLimit {
            for memory in preferences.prefix(3) {
                let memoryText = "- \(memory.memory.summary)\n"
                let tokens = memoryText.count / 4
                if usedTokens + tokens <= tokenLimit {
                    profile += memoryText
                    usedTokens += tokens
                } else { break }
            }
        }
        
        return profile + "\n"
    }
    
    private func selectRelevantMemories(memories: [MemorySearchResult], query: String, tokenLimit: Int) -> String {
        let nonPersonalMemories = memories.filter { 
            $0.memory.type != .personal && $0.memory.type != .preference 
        }.sorted { $0.relevanceScore > $1.relevanceScore }
        
        if nonPersonalMemories.isEmpty { return "" }
        
        var result = ""
        var usedTokens = 0
        
        for memory in nonPersonalMemories {
            let memoryText = "- \(memory.memory.summary) (relevance: \(String(format: "%.2f", memory.relevanceScore)))\n"
            let tokens = memoryText.count / 4
            
            if usedTokens + tokens <= tokenLimit {
                result += memoryText
                usedTokens += tokens
            } else { break }
        }
        
        return result
    }
    
    private func optimizeConversationContext(_ sessionContext: String, tokenLimit: Int) -> String {
        if sessionContext.isEmpty { return "" }
        
        let contextTokens = sessionContext.count / 4
        
        if contextTokens <= tokenLimit {
            return sessionContext
        }
        
        // Smart truncation: Keep more recent messages
        let lines = sessionContext.components(separatedBy: "\n")
        var optimizedLines: [String] = []
        var usedTokens = 0
        
        // Start from the end (most recent) and work backwards
        for line in lines.reversed() {
            let lineTokens = line.count / 4
            if usedTokens + lineTokens <= tokenLimit {
                optimizedLines.insert(line, at: 0)
                usedTokens += lineTokens
            } else { break }
        }
        
        return optimizedLines.joined(separator: "\n")
    }
    
    // MARK: - Context Building (Legacy)
    
    private func buildContextFromMemories(memories: [MemorySearchResult], recentContext: String, query: String) -> String {
        var context = ""
        var usedTokens = 0
        
        // Add user profile/preferences first (highest priority)
        let personalMemories = memories.filter { $0.memory.type == .personal || $0.memory.type == .preference }
        if !personalMemories.isEmpty {
            context += "User Profile:\n"
            for result in personalMemories.prefix(3) {
                let memoryText = "- \(result.memory.summary)\n"
                let estimatedTokens = memoryText.count / 4
                if usedTokens + estimatedTokens < maxContextTokens / 3 {
                    context += memoryText
                    usedTokens += estimatedTokens
                }
            }
            context += "\n"
        }
        
        // Add relevant memories by importance and similarity
        if memories.count > personalMemories.count {
            context += "Relevant Background:\n"
            let otherMemories = memories.filter { $0.memory.type != .personal && $0.memory.type != .preference }
            
            for result in otherMemories.prefix(8) {
                let memoryText = "- \(result.memory.summary) (relevance: \(String(format: "%.2f", result.relevanceScore)))\n"
                let estimatedTokens = memoryText.count / 4
                if usedTokens + estimatedTokens < maxContextTokens * 2 / 3 {
                    context += memoryText
                    usedTokens += estimatedTokens
                }
            }
            context += "\n"
        }
        
        // Add recent conversation context
        if !recentContext.isEmpty {
            let recentTokens = recentContext.count / 4
            if usedTokens + recentTokens < maxContextTokens {
                context += "Recent Conversation:\n\(recentContext)\n"
            }
        }
        
        print("🔍 Built context with \(usedTokens) estimated tokens from \(memories.count) memories")
        return context
    }
    
    // MARK: - Helper Functions
    
    private func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count else { return 0.0 }
        
        let dotProduct = zip(vectorA, vectorB).map(*).reduce(0, +)
        let magnitudeA = sqrt(vectorA.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(vectorB.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    private func findSimilarMemory(userId: String, content: String, threshold: Double = 0.94) async -> VectorMemory? {
        guard let embedding = await generateEmbedding(for: content) else { return nil }
        let results = await searchSimilarMemories(userId: userId, queryEmbedding: embedding, query: content)
        let newType = detectMemoryType(from: content)
        let newKeywords = Set(extractEnhancedKeywords(from: content))

        func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
            if a.isEmpty || b.isEmpty { return 0 }
            return Double(a.intersection(b).count) / Double(a.union(b).count)
        }

        // Only consider memories with very high semantic similarity for updating
        // Require same type and strong keyword overlap to avoid merging different facts
        if let best = results.max(by: { $0.semanticSimilarity < $1.semanticSimilarity }) {
            let sameType = best.memory.type == newType
            let keywordOverlap = jaccard(newKeywords, Set(best.memory.keywords))
            // debug log
            print("🔎 Candidate sim=\(String(format: "%.3f", best.semanticSimilarity)) typeMatch=\(sameType) kwJacc=\(String(format: "%.2f", keywordOverlap)) final=\(String(format: "%.3f", best.relevanceScore))")

            if best.semanticSimilarity >= threshold && sameType && keywordOverlap >= 0.6 {
                print("✅ Similar memory confirmed (same type + high overlap) — will merge")
                return best.memory
            } else {
                print("📝 Not similar enough or different type — will create a new memory")
            }
        }
        return nil
    }

    // Fast dedup via content hash before embedding cost
    private func existsByContentHash(userId: String, content: String) async -> Bool {
        let hash = sha256(content)
        return (await memoryStorage.memory(withContentHash: hash, userId: userId)) != nil
    }

    // Small helper for hashing
    private func sha256(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func updateMemoryAccess(memoryId: String) async {
        await memoryStorage.incrementAccess(for: memoryId)
    }
    

    private func extractEnhancedKeywords(from text: String) -> [String] {
        // Enhanced keyword extraction with entity recognition patterns
        var characterSet = CharacterSet.whitespacesAndNewlines
        characterSet.formUnion(.punctuationCharacters)
        
        let words = text.lowercased()
            .components(separatedBy: characterSet)
            .filter { $0.count > 2 }
            .filter { !commonWords.contains($0) }
        
        // Look for entities (capitalized words, dates, numbers)
        let entities = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { word in
                // Detect proper nouns (capitalized), dates, emails, etc.
                let firstChar = word.first
                return firstChar?.isUppercase == true || 
                       word.contains("@") ||
                       word.contains("/") ||
                       word.allSatisfy { $0.isNumber }
            }
        
        return Array(Set(words + entities.map { $0.lowercased() })).prefix(15).map { String($0) }
    }
    
    private func generateSummary(from content: String) -> String {
        // Simple summarization - in production, use AI summarization
        if content.count <= 100 { return content }
        
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if firstSentence.count > 80 {
            return String(firstSentence.prefix(77)) + "..."
        }
        
        return firstSentence
    }

    // MARK: - Low-signal content filter
    private func isLowSignalMemory(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // Drop very short greetings/acknowledgements
        let lowered = trimmed.lowercased()
        let greetingPatterns = [
            "^hey[!.…]*$",
            "^hi[!.…]*$",
            "^hello[!.…]*$",
            "^ok(ay)?[!.…]*$",
            "^hmm[!.…]*$",
            "^thanks?\\b.*$",
            "^thank you\\b.*$",
            "^yo[!.…]*$",
            "^sup[!.…]*$"
        ]
        for pattern in greetingPatterns {
            if lowered.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        // Very short tokens without nouns are likely noise
        if lowered.count < 6 { return true }
        return false
    }
    
    private func getRecentConversationContext() async -> String {
        // Get last few messages from current session
        guard let sessionId = currentSessionId else { return "" }
        
        let messages = await memoryStorage.recentMessages(sessionId: sessionId, userId: currentUserId, limit: 6).reversed()
        return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
    }
    
    private func getFallbackContext(query: String, sessionId: String? = nil) async -> String {
        // Fallback to keyword-based search if embeddings fail
        let userId = currentUserId
        
        let keywords = extractEnhancedKeywords(from: query)
        let allMemories = await memoryStorage.activeMemories(for: userId, limit: 500)
        var matches: [VectorMemory] = []
        
        for keyword in keywords.prefix(3) {
            let keywordMatches = allMemories.filter { memory in
                memory.keywords.contains { $0.caseInsensitiveCompare(keyword) == .orderedSame }
            }
            matches.append(contentsOf: keywordMatches)
        }
        
        let uniqueMemories = Array(Set(matches.map { $0.id }))
            .compactMap { id in matches.first { $0.id == id } }
            .sorted { $0.importance > $1.importance }
            .prefix(5)
        
        return uniqueMemories.map { "- \($0.summary)" }.joined(separator: "\n")
    }
    
    private let commonWords = Set([
        "the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "who", "boy", "did", "man", "men", "she", "use", "way", "what", "will", "with", "this", "that", "they", "have", "from", "been", "said", "each", "make", "more", "time", "very", "when", "come", "here", "just", "like", "long", "many", "over", "such", "take", "than", "them", "well", "were", "also", "back", "call", "came", "come", "could", "each", "find", "first", "good", "great", "help", "know", "last", "left", "life", "look", "made", "most", "move", "much", "name", "need", "next", "only", "open", "part", "play", "said", "same", "seem", "show", "small", "some", "tell", "turn", "want", "ways", "well", "went", "were", "work", "year", "your"
    ])
    
    // MARK: - Session Management
    
    func startNewSession() -> String {
        let sessionId = UUID().uuidString
        currentSessionId = sessionId
        
        Task {
            await createSession(sessionId: sessionId)
        }
        
        return sessionId
    }
    
    func getCurrentSessionId() -> String {
        if let sessionId = currentSessionId {
            return sessionId
        }
        return startNewSession()
    }
    
    private func createSession(sessionId: String) async {
        let userId = currentUserId
        
        let session = ChatSession(
            id: sessionId,
            userId: userId,
            title: "New Conversation",
            summary: "New conversation started",
            startedAt: Date(),
            lastActivityAt: Date(),
            messageCount: 0,
            totalTokens: 0,
            keyTopics: [],
            isActive: true,
            memoryCount: 0
        )
        
        do {
            try await memoryStorage.saveSession(session)
            print("✅ Created new local session: \(sessionId)")
        } catch {
            print("❌ Failed to create local session: \(error)")
        }
    }
    
    // MARK: - Message Storage
    
    func storeMessage(content: String, role: String, type: MessageType = .text) async {
        let userId = currentUserId
        let sessionId = getCurrentSessionId()
        
        // Estimate token count (rough approximation: 1 token ≈ 4 characters)
        let estimatedTokens = content.count / 4
        
        let message = StoredChatMessage(
            id: UUID().uuidString,
            userId: userId,
            sessionId: sessionId,
            role: role,
            content: content,
            timestamp: Date(),
            type: type,
            tokens: estimatedTokens
        )
        
        do {
            try await memoryStorage.saveMessage(message)
            try await memoryStorage.touchSession(sessionId, userId: userId, tokenDelta: estimatedTokens)
            print("💬 Stored message locally: \(role) - \(content.prefix(50))...")
            
            if role.lowercased() == "user" && type == .text && !isTranscriptionContent(content) && !isLiveSessionSystemMessage(content) {
                // Memory extraction handled elsewhere
            }
        } catch {
            print("❌ Failed to store message locally: \(error)")
        }
    }
    
    // MARK: - Additional Methods for UI Integration
    
    func getAllVectorMemories() async -> [VectorMemory] {
        let userId = currentUserId
        
        print("🔍 VectorMemoryManager: Fetching memories for user ID: \(userId)")
        let memories = await memoryStorage.allMemories(for: userId)
        print("🔍 VectorMemoryManager: Returning \(memories.count) memories from local storage")
        return memories
    }
    
    // Debug method to inspect memory storage
    func debugListMemories() async {
        let memories = await getAllVectorMemories()
        print("🔍 DEBUG: Found \(memories.count) stored memories")
        
        for memory in memories.prefix(5) {
            print("Memory ID: \(memory.id)")
            print("  Type: \(memory.type.rawValue)")
            print("  Summary: \(memory.summary)")
            print("  Keywords: \(memory.keywords)")
            print("  Importance: \(memory.importance)")
            print("  Embedding dims: \(memory.embedding.count)")
            print("  Created: \(memory.createdAt)")
            print("---")
        }
    }
    
    // MARK: - Testing & Debug Functions
    
    func createTestMemory() async {
        print("🧪 Creating test memory...")
        await storeMemoryWithEmbedding(
            content: "Test memory: User is testing the memory system",
            type: .personal,
            source: .explicit,
            importance: 0.8
        )
        print("🧪 Test memory creation completed")
    }
    
    func clearAllMemories() async {
        let userId = currentUserId
        
        print("🗑️ Clearing all memories for user: \(userId)")
        do {
            try await memoryStorage.deleteAllMemories(for: userId)
            print("✅ Cleared memories from local storage")
        } catch {
            print("❌ Error clearing memories locally: \(error)")
        }
    }
    
    func deleteVectorMemory(memoryId: String) async -> Bool {
        do {
            try await memoryStorage.deleteMemory(memoryId)
            print("🗑️ Deleted vector memory locally: \(memoryId)")
            return true
        } catch {
            print("❌ Error deleting vector memory locally: \(error)")
            return false
        }
    }
    

    
    func searchMemoriesWithResults(query: String) async -> [MemorySearchResult] {
        let userId = currentUserId
        
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            print("❌ Failed to generate query embedding for search")
            return []
        }
        
        return await searchSimilarMemories(userId: userId, queryEmbedding: queryEmbedding, query: query)
    }
    
    // MARK: - Content Filtering
    
    private func shouldSkipContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip very short content
        if trimmed.count < 15 {
            return true
        }
        
        // Skip common greetings and casual phrases
        let trivialPatterns = [
            "hi", "hello", "hey", "good morning", "good afternoon", "good evening",
            "how are you", "what's up", "thanks", "thank you", "ok", "okay",
            "yes", "no", "sure", "alright", "cool", "nice", "good", "great",
            "bye", "goodbye", "see you", "later", "talk to you later",
            "lol", "haha", "😊", "😄", "👍", "👋", "🙂"
        ]
        
        let lowerContent = trimmed.lowercased()
        
        // Check if content is just a trivial phrase
        for pattern in trivialPatterns {
            if lowerContent == pattern || lowerContent == "\(pattern)." {
                return true
            }
        }
        
        // Skip if content is mostly punctuation or single words
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.count <= 2 && words.allSatisfy({ $0.count <= 4 }) {
            return true
        }
        
        // Skip if content is mostly emojis or special characters
        let emojiCount = trimmed.unicodeScalars.filter { $0.properties.isEmoji }.count
        if emojiCount > trimmed.count / 2 {
            return true
        }
        
        return false
    }
    
    // MARK: - Server-Side Memory Extraction
    
    private func fetchExtractedFactsFromServer(content: String, sessionId: String?) async -> [ExtractedFact] {
        // Use the server route exposed in Server/api/memory.js
        guard let url = URL(string: "\(AppConfig.serverBaseURL)/api/memory") else {
            print("❌ Invalid extractor URL: \(AppConfig.serverBaseURL)/api/memory")
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Always include API key if available (prod parity)
        if !AppConfig.lucaApiKey.isEmpty {
            request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let body: [String: Any] = [
            "content": content,
            "userId": currentUserId,
            "sessionId": sessionId ?? getCurrentSessionId()
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Memory extraction API response: \(httpResponse.statusCode)")
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let success = json?["success"] as? Bool, success else {
                print("⚠️ Memory extraction failed: \(json?["error"] ?? "Unknown error")")
                return []
            }
            
            guard let factsArray = json?["extractedFacts"] as? [[String: Any]] else {
                print("⚠️ No extractedFacts in response")
                return []
            }
            
            let facts: [ExtractedFact] = factsArray.compactMap { dict in
                guard let text = dict["text"] as? String,
                      let summary = dict["summary"] as? String,
                      let kind = dict["kind"] as? String,
                      let importance = dict["importance"] as? Double else {
                    print("⚠️ Invalid fact format: \(dict)")
                    return nil
                }
                return ExtractedFact(text: text, summary: summary, kind: kind, importance: importance)
            }
            
            print("✅ Server extracted \(facts.count) facts from content")
            return facts
            
        } catch {
            print("❌ Error calling memory extraction API: \(error)")
            return []
        }
    }
    
    // MARK: - Fallback Fact Extraction
    
    private func extractFactsFromContent(_ content: String) async -> [ExtractedFact]? {
        // Simple fallback fact extraction
        let facts = [
            ExtractedFact(
                text: content,
                summary: generateSummary(from: content),
                kind: "general",
                importance: 0.6
            )
        ]
        return facts
    }
    
    private func mapKindToMemoryType(_ kind: String) -> MemoryType {
        switch kind.lowercased() {
        case "personal", "name", "age", "birthday", "location":
            return .personal
        case "preference", "like", "dislike", "favorite":
            return .preference
        case "professional", "work", "job", "career":
            return .professional
        case "goal", "project", "plan", "deadline":
            return .goal
        case "relationship", "friend", "family", "colleague":
            return .relationship
        case "event", "meeting", "appointment":
            return .event
        case "instruction", "remember", "always", "never":
            return .instruction
        default:
            return .knowledge
        }
    }
    
    private func mapSourceToMemorySource(_ source: MemorySource) -> MemorySource {
        switch source {
        case .conversation:
            return .conversation
        case .screenshot:
            return .screenshot
        case .explicit:
            return .explicit
        case .inferred:
            return .inferred
        }
    }
    
    private func extractKeywords(from text: String) -> [String] {
        var characterSet = CharacterSet.whitespacesAndNewlines
        characterSet.formUnion(.punctuationCharacters)
        
        let words = text.lowercased()
            .components(separatedBy: characterSet)
            .filter { $0.count > 2 }
            .filter { !commonWords.contains($0) }
        
        return Array(Set(words)).prefix(10).map { String($0) }
    }
    
    private func similarMemoryExists(userId: String, content: String) async -> Bool {
        // Skip prefix check for very short content to avoid false positives
        if content.count < 50 {
            return false
        }
        
        let contentPrefix = String(content.prefix(100))
        let candidateMemories = await memoryStorage.activeMemories(for: userId, limit: 50)
        
        for memory in candidateMemories {
            let memoryPrefix = String(memory.content.prefix(100))
            if contentPrefix == memoryPrefix ||
                (contentPrefix.count > 80 && memoryPrefix.contains(contentPrefix)) ||
                (memoryPrefix.count > 80 && contentPrefix.contains(memoryPrefix)) {
                print("🔍 Found similar memory by prefix match: \(memory.summary)")
                return true
            }
        }
        return false
    }
    
    // MARK: - Session-based extraction cooldown
    private var lastExtractionBySession: [String: Date] = [:]
    
    /// Centralized memory extraction entry point with gating logic
    func considerMemoryExtraction(userMessage: String, assistantResponse: String, sessionId: String) async {
        // GATE 1: Skip trivial conversations
        guard isSubstantialConversation(userMessage, assistantResponse) else {
            print("⏭️ Skipping trivial conversation")
            return
        }
        
        // GATE 2: Session cooldown (avoid extraction spam)
        guard await shouldExtractFromSession(sessionId) else {
            print("⏭️ Recently extracted from this session")
            return
        }
        
        // GATE 3: Server-side extraction only (more intelligent)
        let combined = "User: \(userMessage)\n\nAssistant: \(assistantResponse)"
        await extractAndStoreMemories(from: combined, sessionId: sessionId, source: .conversation)
    }
    
    private func isSubstantialConversation(_ user: String, _ assistant: String) -> Bool {
        let combined = user + " " + assistant
        let wordCount = combined.split(separator: " ").count
        
        // Check for memory-worthy patterns first (these should always trigger extraction)
        let worthyPatterns = [
            "my name", "i'm", "i am", "i live", "i work", "i study",
            "i like", "i love", "i prefer", "i hate", "i don't like",
            "remember", "always", "never",
            "project", "goal", "working on",
            "nickname", "call me", "my birthday", "my age",
            "my height", "my weight", "my job", "my company"
        ]
        
        let lowerUser = user.lowercased()
        let hasWorthyPattern = worthyPatterns.contains { lowerUser.contains($0) }
        
        // If there's a worthy pattern, always extract (even if short)
        if hasWorthyPattern {
            return true
        }
        
        // Check if assistant acknowledged something to remember
        let lowerAssistant = assistant.lowercased()
        let assistantAcknowledged = lowerAssistant.contains("i'll remember") ||
                                    lowerAssistant.contains("noted") ||
                                    (lowerAssistant.contains("got it") && wordCount > 20)
        
        // If assistant acknowledged, always extract
        if assistantAcknowledged {
            return true
        }
        
        // For other conversations, require meaningful length
        return wordCount >= 15
    }
    
    private func shouldExtractFromSession(_ sessionId: String) async -> Bool {
        if let lastTime = lastExtractionBySession[sessionId],
           Date().timeIntervalSince(lastTime) < 120 { // 2-minute cooldown
            return false
        }
        lastExtractionBySession[sessionId] = Date()
        return true
    }
    
    func extractAndStoreMemories(from content: String, sessionId: String, source: MemorySource) async {
        let userId = currentUserId
        
        print("🧠 Starting memory extraction for content: \(content.prefix(100))...")
        
        // Never extract memories from live transcription text
        if isTranscriptionContent(content) {
            print("⏭️ Skipping extraction for live transcription content")
            return
        }
        
        // Skip extraction for very short or trivial content
        if shouldSkipContent(content) {
            print("⏭️ Skipping trivial content: \(content)")
            return
        }
        
        isProcessingMemory = true
        defer { isProcessingMemory = false }
        
        // Check if we already have this content
        if await similarMemoryExists(userId: userId, content: content) {
            print("📝 Similar memory already exists, skipping extraction")
            return
        }
        
        // Try server-side extraction first
        let extractedFacts = await fetchExtractedFactsFromServer(content: content, sessionId: sessionId)
        
        // Filter out low-importance facts
        let importantFacts = extractedFacts.filter { fact in
            fact.importance >= 0.5 && fact.text.count > 10
        }
        
        if importantFacts.isEmpty {
            print("⚠️ No important facts extracted from content — attempting local fallback extraction")
            if let fallbackFacts = await extractFactsFromContent(content), !fallbackFacts.isEmpty {
                for fact in fallbackFacts {
                    let memoryType = mapKindToMemoryType(fact.kind)
                    await storeMemoryWithEmbedding(
                        content: fact.text,
                        type: memoryType,
                        source: mapSourceToMemorySource(source),
                        importance: fact.importance
                    )
                }
                print("✅ Stored \(fallbackFacts.count) fallback memories")
            } else {
                print("⚠️ Fallback extraction produced no facts")
            }
            return
        }
        
        // Store each important extracted fact as a memory
        for fact in importantFacts {
            let memoryType = mapKindToMemoryType(fact.kind)
            await storeMemoryWithEmbedding(content: fact.text, type: memoryType, source: mapSourceToMemorySource(source), importance: fact.importance)
        }
        
        print("✅ Successfully extracted and stored \(importantFacts.count) important memories")
    }

    // MARK: - Transcription Content Guard
    
    private func isTranscriptionContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only treat as transcription if there is an active listen session
        // and content strongly matches recent transcript/partial markers.
        if SessionTranscriptStore.shared.currentListenSession == nil {
            return false
        }
        if trimmed.hasPrefix("🎤 ") { return true }
        if trimmed.hasPrefix("[Live Meeting Context") { return true }
        if trimmed.contains("Listening session completed:") { return true }

        // Heuristic: match against recent live transcript segments and live partial
        let transcriptStore = SessionTranscriptStore.shared
        if let liveId = transcriptStore.currentListenSession {
            let tenMinutesAgo = Date().addingTimeInterval(-10 * 60)
            let recent = transcriptStore.displaySegments.filter { seg in
                seg.sessionId == liveId && seg.timestamp >= tenMinutesAgo
            }

            // Also consider the current live partial transcript
            var candidateTexts = recent.map { $0.text }
            let livePartial = transcriptStore.livePartialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !livePartial.isEmpty { candidateTexts.append(livePartial) }

            // Normalize function: lowercase, remove punctuation and extra spaces
            func normalize(_ s: String) -> String {
                let lower = s.lowercased()
                let allowed = CharacterSet.alphanumerics.union(.whitespaces)
                let filteredScalars = lower.unicodeScalars.filter { allowed.contains($0) }
                let filtered = String(String.UnicodeScalarView(filteredScalars))
                return filtered.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            }

            let normContent = normalize(trimmed)
            if normContent.isEmpty { return false }

            // Token set similarity (Jaccard)
            func jaccardSimilarity(_ a: String, _ b: String) -> Double {
                let aSet = Set(a.split(separator: " "))
                let bSet = Set(b.split(separator: " "))
                if aSet.isEmpty || bSet.isEmpty { return 0.0 }
                let inter = aSet.intersection(bSet).count
                let union = aSet.union(bSet).count
                return Double(inter) / Double(union)
            }

            for text in candidateTexts {
                let normSeg = normalize(text)
                if normSeg.isEmpty { continue }

                // Direct equality or strong containment for longer strings
                if normContent == normSeg { return true }
                if normContent.count >= 30 && normSeg.contains(normContent) { return true }
                if normSeg.count >= 30 && normContent.contains(normSeg) { return true }

                // High Jaccard similarity implies it's the same utterance (avoid blocking short user facts)
                let sim = jaccardSimilarity(normContent, normSeg)
                if sim >= 0.96 && min(normContent.count, normSeg.count) >= 36 { return true }
            }
        }
        return false
    }

    // Treat prompts derived from transcripts (e.g., auto-generated summary requests) as system/live-session messages
    private func isLiveSessionSystemMessage(_ content: String) -> Bool {
        let lower = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("please provide a brief summary of this audio transcript") { return true }
        if lower.contains("[live meeting context") { return true }
        if lower.contains("current transcription") { return true }
        // Block obvious auto-generated summary/analysis prompts while a listen session is active
        if SessionTranscriptStore.shared.currentListenSession != nil {
            let patterns = [
                "summary of this audio transcript",
                "summarize this transcript",
                "based on the transcript",
                "meeting transcript",
                "live meeting"
            ]
            for p in patterns { if lower.contains(p) { return true } }
        }
        return false
    }
    
    private func getRecentMessages(sessionId: String, limit: Int) async -> [StoredChatMessage] {
        await memoryStorage.recentMessages(sessionId: sessionId, userId: currentUserId, limit: limit)
    }
    
    private func getSessionSummary(sessionId: String) async -> String? {
        return await memoryStorage.session(withId: sessionId)?.summary
    }
    
    // MARK: - Enhanced Relevance Scoring
    
    private func calculateFuzzyKeywordMatch(query: String, keywords: [String]) -> Double {
        let queryWords = query.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0.count > 2 }
        
        var matchScore = 0.0
        let totalWords = Double(queryWords.count)
        
        if totalWords == 0 { return 0.0 }
        
        for queryWord in queryWords {
            for keyword in keywords {
                let similarity = stringSimilarity(queryWord, keyword.lowercased())
                if similarity > 0.7 { // 70% similarity threshold
                    matchScore += similarity
                    break // Count each query word only once
                }
            }
        }
        
        return min(1.0, matchScore / totalWords)
    }
    
    private func calculateTypeRelevance(memoryType: MemoryType, query: String) -> Double {
        let lowercaseQuery = query.lowercased()
        
        switch memoryType {
        case .personal:
            // High relevance for identity/personal questions
            if lowercaseQuery.contains("my name") || lowercaseQuery.contains("i am") || 
               lowercaseQuery.contains("who am i") || lowercaseQuery.contains("about me") {
                return 1.0
            }
            return 0.3
            
        case .preference:
            // High relevance for preference/opinion questions
            if lowercaseQuery.contains("like") || lowercaseQuery.contains("prefer") || 
               lowercaseQuery.contains("favorite") || lowercaseQuery.contains("love") ||
               lowercaseQuery.contains("hate") || lowercaseQuery.contains("dislike") {
                return 1.0
            }
            return 0.4
            
        case .professional:
            // High relevance for work/career questions
            if lowercaseQuery.contains("work") || lowercaseQuery.contains("job") || 
               lowercaseQuery.contains("career") || lowercaseQuery.contains("study") ||
               lowercaseQuery.contains("university") || lowercaseQuery.contains("college") {
                return 1.0
            }
            return 0.3
            
        case .goal:
            // High relevance for future/planning questions
            if lowercaseQuery.contains("plan") || lowercaseQuery.contains("goal") || 
               lowercaseQuery.contains("want to") || lowercaseQuery.contains("future") {
                return 1.0
            }
            return 0.2
            
        case .instruction:
            // High relevance for how-to questions
            if lowercaseQuery.contains("how") || lowercaseQuery.contains("remember") ||
               lowercaseQuery.contains("always") || lowercaseQuery.contains("never") {
                return 1.0
            }
            return 0.4
            
        case .knowledge, .relationship, .event:
            // Standard relevance for general information
            return 0.5
        }
    }
    
    private func stringSimilarity(_ str1: String, _ str2: String) -> Double {
        if str1 == str2 { return 1.0 }
        if str1.isEmpty || str2.isEmpty { return 0.0 }
        
        // Simple Levenshtein distance-based similarity
        let maxLen = max(str1.count, str2.count)
        let distance = levenshteinDistance(str1, str2)
        return max(0.0, 1.0 - Double(distance) / Double(maxLen))
    }
    
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let m = str1.count
        let n = str2.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        let str1Array = Array(str1)
        let str2Array = Array(str2)
        
        for i in 1...m {
            for j in 1...n {
                let cost = str1Array[i-1] == str2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    // MARK: - Memory Decay System
    
    func decayMemories() async {
        let userId = currentUserId
        let memories = await memoryStorage.activeMemories(for: userId, limit: 500)
        
        for memory in memories {
            let ageInDays = Date().timeIntervalSince(memory.createdAt) / (24 * 60 * 60)
            let accessFactor = max(0.5, 1.0 - (Double(memory.accessCount) * 0.1))
            let ageFactor = max(0.1, 1.0 - (ageInDays * 0.01))
            let newDecayFactor = memory.decayFactor * accessFactor * ageFactor
            
            var updated = memory
            var needsUpdate = false
            
            if abs(newDecayFactor - memory.decayFactor) > 0.05 {
                updated = updated.updating(decayFactor: newDecayFactor)
                needsUpdate = true
            }
            
            if ageInDays > 365 && memory.accessCount == 0 && memory.importance < 0.5 && memory.isActive {
                updated = updated.updating(isActive: false)
                needsUpdate = true
                print("📉 Deactivated old unused memory: \(memory.summary)")
            }
            
            if needsUpdate {
                do {
                    try await memoryStorage.updateMemory(updated)
                } catch {
                    print("❌ Error updating decayed memory: \(error)")
                }
            }
        }
        
        print("🕒 Completed memory decay process")
    }
    
    // MARK: - Intelligent Memory Type Detection
    
    private func detectMemoryType(from content: String) -> MemoryType {
        let lowerContent = content.lowercased()
        
        // Personal information patterns
        if lowerContent.contains("my name") || lowerContent.contains("i'm ") || lowerContent.contains("i am ") ||
           lowerContent.contains("i live") || lowerContent.contains("my birthday") || lowerContent.contains("my age") ||
           lowerContent.contains("i was born") || lowerContent.contains("i come from") {
            return .personal
        }
        
        // Preference patterns
        if lowerContent.contains("i like") || lowerContent.contains("i love") || lowerContent.contains("i prefer") ||
           lowerContent.contains("i hate") || lowerContent.contains("i enjoy") || lowerContent.contains("my favorite") ||
           lowerContent.contains("i don't like") || lowerContent.contains("i dislike") {
            return .preference
        }
        
        // Professional patterns
        if lowerContent.contains("i work") || lowerContent.contains("i'm a") || lowerContent.contains("my job") ||
           lowerContent.contains("i study") || lowerContent.contains("career") || lowerContent.contains("company") ||
           lowerContent.contains("university") || lowerContent.contains("college") {
            return .professional
        }
        
        // Goal patterns
        if lowerContent.contains("project") || lowerContent.contains("goal") || lowerContent.contains("working on") ||
           lowerContent.contains("trying to") || lowerContent.contains("planning to") || lowerContent.contains("want to") ||
           lowerContent.contains("deadline") || lowerContent.contains("target") {
            return .goal
        }
        
        // Instruction patterns
        if lowerContent.contains("remember") || lowerContent.contains("always") || lowerContent.contains("never") ||
           lowerContent.contains("please") || lowerContent.contains("help me") || lowerContent.contains("remind me") ||
           lowerContent.contains("i need you to") || lowerContent.contains("can you") {
            return .instruction
        }
        
        // Relationship patterns
        if lowerContent.contains("my friend") || lowerContent.contains("my family") || lowerContent.contains("my colleague") ||
           lowerContent.contains("my partner") || lowerContent.contains("my wife") || lowerContent.contains("my husband") {
            return .relationship
        }
        
        // Event patterns
        if lowerContent.contains("next week") || lowerContent.contains("tomorrow") || lowerContent.contains("meeting") ||
           lowerContent.contains("appointment") || lowerContent.contains("event") || lowerContent.contains("vacation") {
            return .event
        }
        
        // Default to knowledge for general information
        return .knowledge
    }
}

// Note: String.sha256 extension is defined in MemoryManager.swift

