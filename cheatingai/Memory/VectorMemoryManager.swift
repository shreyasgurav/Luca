import Foundation
import FirebaseFirestore
import FirebaseAuth
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
    
    private let db = Firestore.firestore()
    private let embeddingCache = NSCache<NSString, NSArray>()
    private let maxContextTokens = 2000
    private let maxRetrievedMemories = 15
    
    @Published var isProcessingMemory = false
    @Published var currentSessionId: String?
    
    private init() {
        setupEmbeddingCache()
    }
    
    private func setupEmbeddingCache() {
        embeddingCache.countLimit = 100 // Cache up to 100 embeddings
        embeddingCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    // MARK: - Current User
    
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    // MARK: - Enhanced Memory Storage with Embeddings
    
    func storeMemoryWithEmbedding(content: String, type: MemoryType, source: MemorySource, importance: Double = 0.7) async {
        guard let userId = currentUserId else { 
            print("❌ storeMemoryWithEmbedding: No current user ID available")
            return 
        }
        
        print("🔄 storeMemoryWithEmbedding: Starting storage for user ID: \(userId)")
        print("   - Content: \(content.prefix(100))...")
        print("   - Type: \(type.rawValue)")
        
        isProcessingMemory = true
        defer { isProcessingMemory = false }
        
        // Check for similar existing memories using vector similarity
        // Only update if content is 95%+ similar (e.g., exact duplicates or near-duplicates)
        if let similarMemory = await findSimilarMemory(userId: userId, content: content, threshold: 0.95) {
            // Update existing memory instead of creating duplicate
            await updateMemoryAccess(memoryId: similarMemory.id)
            print("📝 Updated similar existing memory")
            return
        }
        
        // Generate embedding for the content
        guard let embedding = await generateEmbedding(for: content) else {
            print("❌ Failed to generate embedding for content")
            return
        }
        
        let keywords = extractEnhancedKeywords(from: content)
        let summary = generateSummary(from: content)
        
        let memory = VectorMemory(
            id: UUID().uuidString,
            userId: userId,
            type: type,
            content: content,
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
            isActive: true
        )
        
        await storeVectorMemory(memory)
    }
    
    private func storeVectorMemory(_ memory: VectorMemory) async {
        do {
            print("💾 Storing memory to Firebase:")
            print("   - Collection: vector_memories")
            print("   - Document ID: \(memory.id)")
            print("   - User ID: \(memory.userId)")
            print("   - Summary: \(memory.summary)")
            print("   - Type: \(memory.type.rawValue)")
            
            try await db.collection("vector_memories").document(memory.id).setData(from: memory)
            print("✅ Successfully stored vector memory: \(memory.summary) (ID: \(memory.id))")
        } catch {
            print("❌ Failed to store vector memory: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - OpenAI Embedding Generation
    
    private func generateEmbedding(for text: String) async -> [Double]? {
        // Check cache first
        let cacheKey = NSString(string: SHA256.hash(data: Data(text.utf8)).compactMap { String(format: "%02x", $0) }.joined())
        if let cachedEmbedding = embeddingCache.object(forKey: cacheKey) as? [Double] {
            return cachedEmbedding
        }
        
        // Call OpenAI embedding API
        guard let url = URL(string: "http://localhost:3000/api/embedding") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "userId": currentUserId ?? ""
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
        guard let userId = currentUserId else { return "" }
        
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
        
        // Build comprehensive context with both long-term memories and session context
        return buildEnhancedContextFromMemories(
            memories: relevantMemories, 
            sessionContext: sessionContext, 
            query: query,
            sessionId: actualSessionId
        )
    }
    
    private func searchSimilarMemories(userId: String, queryEmbedding: [Double], query: String) async -> [MemorySearchResult] {
        do {
            // Fetch active memories for the user
            let memoryQuery = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
                .whereField("isActive", isEqualTo: true)
                .limit(to: 100) // Fetch more for better filtering
            
            let snapshot = try await memoryQuery.getDocuments()
            var searchResults: [MemorySearchResult] = []
            
            for document in snapshot.documents {
                guard let memory = try? document.data(as: VectorMemory.self) else { continue }
                
                // Enhanced relevance scoring algorithm (ChatGPT-inspired)
                let semantic = cosineSimilarity(queryEmbedding, memory.embedding)
                
                // Importance scoring (30% weight)
                let importanceBoost = memory.importance * 0.3
                
                // Recency scoring with decay curve (15% weight)
                let daysSinceCreated = Date().timeIntervalSince(memory.createdAt) / (24 * 60 * 60)
                let recencyBoost = max(0, 0.15 * exp(-daysSinceCreated / 30.0)) // 30-day decay
                
                // Access frequency scoring (10% weight)
                let accessBoost = min(0.1, Double(memory.accessCount) * 0.02)
                
                // Memory decay factor (5% weight)
                let decayBoost = memory.importance * memory.decayFactor * 0.05
                
                // Keyword exact match bonus (20% potential boost)
                let keywordMatch = memory.keywords.contains { query.lowercased().contains($0.lowercased()) }
                let exactKeywordBoost = keywordMatch ? 0.2 : 0.0
                
                // Fuzzy keyword matching (10% potential boost)
                let fuzzyKeywordBoost = calculateFuzzyKeywordMatch(query: query, keywords: memory.keywords) * 0.1
                
                // Type relevance boost (certain types more relevant for certain queries)
                let typeBoost = calculateTypeRelevance(memoryType: memory.type, query: query) * 0.1
                
                // Final weighted score
                let finalScore = semantic + importanceBoost + recencyBoost + accessBoost + decayBoost + exactKeywordBoost + fuzzyKeywordBoost + typeBoost
                
                // Only include memories above similarity threshold
                if semantic > 0.3 || keywordMatch {
                    let result = MemorySearchResult(
                        memory: memory,
                        relevanceScore: finalScore,
                        semanticSimilarity: semantic,
                        importanceBoost: importanceBoost,
                        recencyBoost: recencyBoost
                    )
                    searchResults.append(result)
                    
                    // Update access count for retrieved memories
                    Task {
                        await updateMemoryAccess(memoryId: memory.id)
                    }
                }
            }
            
            // Sort by relevance score and return top results
            let sortedResults = searchResults
                .sorted { $0.relevanceScore > $1.relevanceScore }
                .prefix(maxRetrievedMemories)
                .map { $0 }
            
            // debug
            let topDebug = sortedResults.prefix(5)
            for r in topDebug {
                print("DBG memory \(r.memory.id) sem:\(String(format: "%.3f", r.semanticSimilarity)) final:\(String(format: "%.3f", r.relevanceScore)) tags:\(r.memory.keywords)")
            }
            
            return Array(sortedResults)
            
        } catch {
            print("❌ Error searching memories: \(error)")
            return []
        }
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
    
    private func buildEnhancedContextFromMemories(
        memories: [MemorySearchResult], 
        sessionContext: String, 
        query: String,
        sessionId: String
    ) -> String {
        var context = ""
        var usedTokens = 0
        let maxTokens = maxContextTokens
        
        // Token allocation strategy (based on ChatGPT approach):
        // 25% for user profile, 35% for relevant memories, 40% for recent conversation
        let profileTokenLimit = maxTokens / 4
        let memoryTokenLimit = (maxTokens * 35) / 100
        let conversationTokenLimit = (maxTokens * 40) / 100
        
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
        
        print("🧠 Built enhanced context: \(usedTokens) tokens, \(memories.count) memories, session: \(sessionId)")
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
    
    private func findSimilarMemory(userId: String, content: String, threshold: Double = 0.95) async -> VectorMemory? {
        guard let embedding = await generateEmbedding(for: content) else { return nil }
        let results = await searchSimilarMemories(userId: userId, queryEmbedding: embedding, query: content)

        // Only consider memories with very high semantic similarity for updating
        // This ensures we only update truly similar content, not just related content
        if let best = results.max(by: { $0.semanticSimilarity < $1.semanticSimilarity }) {
            // debug log
            print("🔎 Best candidate similarity: \(String(format: "%.3f", best.semanticSimilarity)), finalScore: \(String(format: "%.3f", best.relevanceScore))")
            print("🔍 Similarity threshold: \(threshold) - Will update: \(best.semanticSimilarity >= threshold)")
            
            // Only update if semantic similarity is very high (95%+ similar)
            // This prevents different facts about the same person from being merged
            if best.semanticSimilarity >= threshold {
                print("✅ Found truly similar memory - updating existing")
                return best.memory
            } else {
                print("📝 Content is different enough - creating new memory")
            }
        }
        return nil
    }
    
    private func updateMemoryAccess(memoryId: String) async {
        do {
            let memoryRef = db.collection("vector_memories").document(memoryId)
            try await memoryRef.updateData([
                "lastAccessedAt": FieldValue.serverTimestamp(),
                "accessCount": FieldValue.increment(Int64(1))
            ])
        } catch {
            print("❌ Failed to update memory access: \(error)")
        }
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
        if content.count <= 100 {
            return content
        }
        
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let firstSentence = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if firstSentence.count > 80 {
            return String(firstSentence.prefix(77)) + "..."
        }
        
        return firstSentence
    }
    
    private func getRecentConversationContext() async -> String {
        // Get last few messages from current session
        guard let sessionId = currentSessionId else { return "" }
        
        do {
            let messagesQuery = db.collection("messages")
                .whereField("sessionId", isEqualTo: sessionId)
                .order(by: "timestamp", descending: true)
                .limit(to: 6)
            
            let snapshot = try await messagesQuery.getDocuments()
            let messages = snapshot.documents.compactMap { doc in
                try? doc.data(as: StoredChatMessage.self)
            }.reversed()
            
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        } catch {
            print("❌ Error fetching recent context: \(error)")
            return ""
        }
    }
    
    private func getFallbackContext(query: String, sessionId: String? = nil) async -> String {
        // Fallback to keyword-based search if embeddings fail
        guard let userId = currentUserId else { return "" }
        
        do {
            let keywords = extractEnhancedKeywords(from: query)
            var memories: [VectorMemory] = []
            
            for keyword in keywords.prefix(3) {
                let keywordQuery = db.collection("vector_memories")
                    .whereField("userId", isEqualTo: userId)
                    .whereField("keywords", arrayContains: keyword)
                    .limit(to: 5)
                
                let snapshot = try await keywordQuery.getDocuments()
                let keywordMemories = snapshot.documents.compactMap { doc in
                    try? doc.data(as: VectorMemory.self)
                }
                memories.append(contentsOf: keywordMemories)
            }
            
            // Remove duplicates and sort by importance
            let uniqueMemories = Array(Set(memories.map { $0.id }))
                .compactMap { id in memories.first { $0.id == id } }
                .sorted { $0.importance > $1.importance }
                .prefix(5)
            
            return uniqueMemories.map { "- \($0.summary)" }.joined(separator: "\n")
            
        } catch {
            print("❌ Error in fallback search: \(error)")
            return ""
        }
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
        guard let userId = currentUserId else { return }
        
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
            try await db.collection("sessions").document(sessionId).setData(from: session)
            print("✅ Created new session: \(sessionId)")
        } catch {
            print("❌ Failed to create session: \(error)")
        }
    }
    
    // MARK: - Message Storage
    
    func storeMessage(content: String, role: String, type: MessageType = .text) async {
        guard let userId = currentUserId else { return }
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
            try await db.collection("messages").document(message.id).setData(from: message)
            print("💬 Stored message: \(role) - \(content.prefix(50))...")
            
            // Update session
            await updateSessionActivity(sessionId: sessionId)
        } catch {
            print("❌ Failed to store message: \(error)")
        }
    }
    
    private func updateSessionActivity(sessionId: String) async {
        do {
            let sessionRef = db.collection("sessions").document(sessionId)
            // Use setData with merge to create if doesn't exist, update if it does
            try await sessionRef.setData([
                "lastActivityAt": FieldValue.serverTimestamp(),
                "messageCount": FieldValue.increment(Int64(1))
            ], merge: true)
        } catch {
            print("❌ Failed to update session activity: \(error)")
        }
    }
    
    // MARK: - Additional Methods for UI Integration
    
    func getAllVectorMemories() async -> [VectorMemory] {
        guard let userId = currentUserId else { 
            print("❌ VectorMemoryManager: No current user ID available")
            return [] 
        }
        
        print("🔍 VectorMemoryManager: Fetching memories for user ID: \(userId)")
        
        do {
            let query = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
            
            let snapshot = try await query.getDocuments()
            print("🔍 VectorMemoryManager: Found \(snapshot.documents.count) documents in query")
            
            let memories = snapshot.documents.compactMap { doc in
                do {
                    let memory = try doc.data(as: VectorMemory.self)
                    print("✅ Successfully decoded memory: \(memory.id) - \(memory.summary)")
                    return memory
                } catch {
                    print("❌ Failed to decode memory from document \(doc.documentID): \(error)")
                    return nil
                }
            }
            
            print("🔍 VectorMemoryManager: Returning \(memories.count) memories")
            return memories
        } catch {
            print("❌ Error fetching all vector memories: \(error)")
            return []
        }
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
        guard let userId = currentUserId else { 
            print("❌ No user ID available for clearing memories")
            return 
        }
        
        print("🗑️ Clearing all memories for user: \(userId)")
        
        do {
            let query = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
            
            let snapshot = try await query.getDocuments()
            
            for document in snapshot.documents {
                try await document.reference.delete()
                print("🗑️ Deleted memory: \(document.documentID)")
            }
            
            print("✅ Cleared \(snapshot.documents.count) memories")
        } catch {
            print("❌ Error clearing memories: \(error)")
        }
    }
    
    func deleteVectorMemory(memoryId: String) async {
        do {
            try await db.collection("vector_memories").document(memoryId).delete()
            print("🗑️ Deleted vector memory: \(memoryId)")
        } catch {
            print("❌ Error deleting vector memory: \(error)")
        }
    }
    

    
    func searchMemoriesWithResults(query: String) async -> [MemorySearchResult] {
        guard let userId = currentUserId else { return [] }
        
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            print("❌ Failed to generate query embedding for search")
            return []
        }
        
        return await searchSimilarMemories(userId: userId, queryEmbedding: queryEmbedding, query: query)
    }
    
    // MARK: - Fact Extraction
    
    private func extractFactsFromContent(_ content: String) async -> [ExtractedFact]? {
        // Simple fact extraction - in production, use OpenAI for better extraction
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
        do {
            let contentPrefix = String(content.prefix(100))
            let query = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
                .whereField("isActive", isEqualTo: true)
                .limit(to: 10)
            
            let snapshot = try await query.getDocuments()
            
            for document in snapshot.documents {
                if let memory = try? document.data(as: VectorMemory.self) {
                    if memory.content.hasPrefix(contentPrefix) || contentPrefix.contains(String(memory.content.prefix(50))) {
                        return true
                    }
                }
            }
            return false
        } catch {
            print("❌ Error checking for similar memories: \(error)")
            return false
        }
    }
    
    func extractAndStoreMemories(from content: String, sessionId: String, source: MemorySource) async {
        guard let userId = currentUserId else { return }
        
        isProcessingMemory = true
        defer { isProcessingMemory = false }
        
        // Check if we already have this content
        if await similarMemoryExists(userId: userId, content: content) {
            print("📝 Similar memory already exists, skipping")
            return
        }
        
        // Extract structured facts
        guard let extractedFacts = await extractFactsFromContent(content) else {
            print("⚠️ No facts extracted from content")
            return
        }
        
        // Store each extracted fact as a memory
        for fact in extractedFacts {
            let memoryType = mapKindToMemoryType(fact.kind)
            let keywords = extractKeywords(from: fact.text)
            
            let memory = VectorMemory(
                id: UUID().uuidString,
                userId: userId,
                type: memoryType,
                content: fact.text,
                summary: fact.summary,
                keywords: keywords,
                embedding: [], // Will be generated when stored
                importance: fact.importance,
                confidence: 0.8,
                source: mapSourceToMemorySource(source),
                context: MemoryContext(
                    sessionId: sessionId,
                    messageId: nil,
                    timestamp: Date(),
                    conversationTopic: nil,
                    relatedMemories: []
                ),
                createdAt: Date(),
                lastAccessedAt: Date(),
                accessCount: 0,
                decayFactor: 1.0,
                isActive: true
            )
            
            await storeMemoryWithEmbedding(content: fact.text, type: memoryType, source: mapSourceToMemorySource(source), importance: fact.importance)
        }
    }
    
    private func getRecentMessages(sessionId: String, limit: Int) async -> [StoredChatMessage] {
        do {
            let query = db.collection("messages")
                .whereField("sessionId", isEqualTo: sessionId)
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
            
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { doc in
                try? doc.data(as: StoredChatMessage.self)
            }
        } catch {
            print("❌ Error fetching recent messages: \(error)")
            return []
        }
    }
    
    private func getSessionSummary(sessionId: String) async -> String? {
        do {
            let document = try await db.collection("sessions").document(sessionId).getDocument()
            if let session = try? document.data(as: ChatSession.self) {
                return session.summary
            }
            return nil
        } catch {
            print("❌ Error fetching session summary: \(error)")
            return nil
        }
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
        guard let userId = currentUserId else { return }
        
        do {
            let query = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
                .whereField("isActive", isEqualTo: true)
            
            let snapshot = try await query.getDocuments()
            
            for document in snapshot.documents {
                guard let memory = try? document.data(as: VectorMemory.self) else { continue }
                
                // Calculate age in days
                let ageInDays = Date().timeIntervalSince(memory.createdAt) / (24 * 60 * 60)
                
                // Apply decay based on age and access frequency
                let accessFactor = max(0.5, 1.0 - (Double(memory.accessCount) * 0.1))
                let ageFactor = max(0.1, 1.0 - (ageInDays * 0.01))
                let newDecayFactor = memory.decayFactor * accessFactor * ageFactor
                
                // Only update if decay factor changed significantly
                if abs(newDecayFactor - memory.decayFactor) > 0.05 {
                    try await document.reference.updateData([
                        "decayFactor": newDecayFactor
                    ])
                }
                
                // Deactivate very old, unused memories
                if ageInDays > 365 && memory.accessCount == 0 && memory.importance < 0.5 {
                    try await document.reference.updateData([
                        "isActive": false
                    ])
                    print("📉 Deactivated old unused memory: \(memory.summary)")
                }
            }
            
            print("🕒 Completed memory decay process")
        } catch {
            print("❌ Error during memory decay: \(error)")
        }
    }
}

// Note: String.sha256 extension is defined in MemoryManager.swift
