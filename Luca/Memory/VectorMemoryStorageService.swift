import Foundation

actor VectorMemoryStorageService {
    static let shared = VectorMemoryStorageService()
    
    private var memories: [VectorMemory]
    private var sessions: [ChatSession]
    private var messages: [StoredChatMessage]
    
    private let memoriesURL: URL
    private let sessionsURL: URL
    private let messagesURL: URL
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = baseDirectory.appendingPathComponent("LucaVectorData", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        memoriesURL = directory.appendingPathComponent("vector_memories.json")
        sessionsURL = directory.appendingPathComponent("chat_sessions.json")
        messagesURL = directory.appendingPathComponent("chat_messages.json")
        
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        memories = Self.load(from: memoriesURL, using: decoder) ?? []
        sessions = Self.load(from: sessionsURL, using: decoder) ?? []
        messages = Self.load(from: messagesURL, using: decoder) ?? []
    }
    
    // MARK: - Public Memory APIs
    
    func saveMemory(_ memory: VectorMemory) async throws {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
        try persistMemories()
    }
    
    func memory(withContentHash hash: String, userId: String) async -> VectorMemory? {
        memories.first { $0.userId == userId && $0.contentHash == hash }
    }
    
    func activeMemories(for userId: String, limit: Int = 200) async -> [VectorMemory] {
        memories
            .filter { $0.userId == userId && $0.isActive }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }
    
    func allMemories(for userId: String) async -> [VectorMemory] {
        memories
            .filter { $0.userId == userId }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    func updateMemory(_ memory: VectorMemory) async throws {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else {
            return try await saveMemory(memory)
        }
        memories[index] = memory
        try persistMemories()
    }
    
    func incrementAccess(for memoryId: String) async {
        guard let index = memories.firstIndex(where: { $0.id == memoryId }) else { return }
        var memory = memories[index]
        memory = memory.updating(
            lastAccessedAt: Date(),
            accessCount: memory.accessCount + 1
        )
        memories[index] = memory
        try? persistMemories()
    }
    
    func deleteMemory(_ id: String) async throws {
        memories.removeAll { $0.id == id }
        try persistMemories()
    }
    
    func deleteAllMemories(for userId: String) async throws {
        memories.removeAll { $0.userId == userId }
        try persistMemories()
    }
    
    // MARK: - Session & Message APIs
    
    func saveSession(_ session: ChatSession) async throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        try persistSessions()
    }
    
    func session(withId id: String) async -> ChatSession? {
        sessions.first { $0.id == id }
    }
    
    func touchSession(_ sessionId: String, userId: String, tokenDelta: Int) async throws {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            var session = sessions[index]
            let updated = ChatSession(
                id: session.id,
                userId: session.userId,
                title: session.title,
                summary: session.summary,
                startedAt: session.startedAt,
                lastActivityAt: Date(),
                messageCount: session.messageCount + 1,
                totalTokens: session.totalTokens + tokenDelta,
                keyTopics: session.keyTopics,
                isActive: session.isActive,
                memoryCount: session.memoryCount
            )
            sessions[index] = updated
        } else {
            let session = ChatSession(
                id: sessionId,
                userId: userId,
                title: "Conversation",
                summary: "",
                startedAt: Date(),
                lastActivityAt: Date(),
                messageCount: 1,
                totalTokens: tokenDelta,
                keyTopics: [],
                isActive: true,
                memoryCount: 0
            )
            sessions.append(session)
        }
        try persistSessions()
    }
    
    func saveMessage(_ message: StoredChatMessage) async throws {
        messages.append(message)
        try persistMessages()
    }
    
    func recentMessages(sessionId: String, userId: String, limit: Int) async -> [StoredChatMessage] {
        messages
            .filter { $0.sessionId == sessionId && $0.userId == userId }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Helpers
    
    private static func load<T: Decodable>(from url: URL, using decoder: JSONDecoder) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            print("⚠️ Failed to load \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    private func persistMemories() throws {
        let data = try encoder.encode(memories)
        try data.write(to: memoriesURL, options: .atomic)
    }
    
    private func persistSessions() throws {
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsURL, options: .atomic)
    }
    
    private func persistMessages() throws {
        let data = try encoder.encode(messages)
        try data.write(to: messagesURL, options: .atomic)
    }
}

