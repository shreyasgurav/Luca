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
        guard let userId = currentUserId else { return }
        
        isProcessingMemory = true
        defer { isProcessingMemory = false }
        
        // Check for similar existing memories using vector similarity
        if let similarMemory = await findSimilarMemory(userId: userId, content: content, threshold: 0.9) {
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
            try await db.collection("vector_memories").document(memory.id).setData(from: memory)
            print("🧠 Stored vector memory: \(memory.summary)")
        } catch {
            print("❌ Failed to store vector memory: \(error)")
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
    
    func getRelevantMemoriesWithContext(for query: String) async -> String {
        guard let userId = currentUserId else { return "" }
        
        // Generate embedding for the query
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            print("❌ Failed to generate query embedding")
            return await getFallbackContext(query: query)
        }
        
        // Retrieve semantically similar memories
        let relevantMemories = await searchSimilarMemories(
            userId: userId,
            queryEmbedding: queryEmbedding,
            query: query
        )
        
        // Get recent conversation context
        let recentContext = await getRecentConversationContext()
        
        // Build comprehensive context
        return buildContextFromMemories(memories: relevantMemories, recentContext: recentContext, query: query)
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
                
                // Calculate semantic similarity using cosine similarity
                let semantic = cosineSimilarity(queryEmbedding, memory.embedding)
                let importanceBoost = memory.importance * 0.3
                let daysSinceCreated = Date().timeIntervalSince(memory.createdAt) / (24 * 60 * 60)
                let recencyBoost = max(0, 0.2 - (daysSinceCreated * 0.01))
                let accessBoost = min(0.1, Double(memory.accessCount) * 0.01)
                let decayBoost = memory.importance * memory.decayFactor * 0.1
                let baseScore = semantic + importanceBoost + recencyBoost + accessBoost + decayBoost
                let keywordMatch = memory.keywords.contains { query.lowercased().contains($0.lowercased()) }
                let keywordBoost = keywordMatch ? 0.15 : 0.0
                let finalScore = baseScore + keywordBoost
                
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
    
    // MARK: - Context Building
    
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
    
    private func findSimilarMemory(userId: String, content: String, threshold: Double = 0.82) async -> VectorMemory? {
        guard let embedding = await generateEmbedding(for: content) else { return nil }
        let results = await searchSimilarMemories(userId: userId, queryEmbedding: embedding, query: content)

        // prefer results with high final score (semantic + importance + keyword)
        if let best = results.max(by: { $0.relevanceScore < $1.relevanceScore }) {
            // debug log
            print("🔎 Best candidate similarity: \(String(format: "%.3f", best.semanticSimilarity)), finalScore: \(String(format: "%.3f", best.relevanceScore))")
            // accept if final score is reasonably high OR semantic similarity >= threshold
            if best.relevanceScore >= 0.60 || best.semanticSimilarity >= threshold {
                return best.memory
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
    
    private func getFallbackContext(query: String) async -> String {
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
        guard let userId = currentUserId else { return [] }
        
        do {
            let query = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
            
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { doc in
                try? doc.data(as: VectorMemory.self)
            }
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
    
    func deleteVectorMemory(memoryId: String) async {
        do {
            try await db.collection("vector_memories").document(memoryId).delete()
            print("🗑️ Deleted vector memory: \(memoryId)")
        } catch {
            print("❌ Error deleting vector memory: \(error)")
        }
    }
    
    func clearAllMemories() async {
        guard let userId = currentUserId else { return }
        
        do {
            let query = db.collection("vector_memories")
                .whereField("userId", isEqualTo: userId)
                .whereField("isActive", isEqualTo: true)
            
            let snapshot = try await query.getDocuments()
            
            for document in snapshot.documents {
                try await document.reference.delete()
            }
            
            print("🗑️ Cleared all vector memories for user")
        } catch {
            print("❌ Error clearing all memories: \(error)")
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
