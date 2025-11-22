import Foundation

/// Local session storage service (replaces Firestore persistence).
///
/// Sessions are serialized to JSON inside the user's Application Support directory.
final class LocalSessionStorageService {
    static let shared = LocalSessionStorageService()
    
    private let storageQueue = DispatchQueue(label: "com.luca.sessionStorage", qos: .utility)
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let pageSize = 20
    
    private var cachedSessions: [ListenSession] = []
    private var paginationIndex: Int = 0
    private var isCacheLoaded = false
    
    private init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = baseDirectory.appendingPathComponent("LucaSessions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storageURL = directory.appendingPathComponent("sessions.json")
        
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public API
    
    func resetSessionsPagination() {
        storageQueue.sync {
            paginationIndex = 0
        }
    }
    
    func loadSessions() async throws -> [ListenSession] {
        try ensureCacheLoaded()
        return storageQueue.sync {
            paginationIndex = min(pageSize, cachedSessions.count)
            return Array(cachedSessions.prefix(paginationIndex))
        }
    }
    
    func loadMoreSessions(limit: Int = 20) async throws -> [ListenSession] {
        try ensureCacheLoaded()
        return storageQueue.sync {
            guard paginationIndex < cachedSessions.count else { return [] }
            let nextIndex = min(paginationIndex + limit, cachedSessions.count)
            let slice = Array(cachedSessions[paginationIndex..<nextIndex])
            paginationIndex = nextIndex
            return slice
        }
    }
    
    func saveSession(_ session: ListenSession, finalTranscript: String? = nil) async throws {
        try ensureCacheLoaded()
        try storageQueue.sync {
            var updatedSession = session
            if let finalTranscript, !finalTranscript.isEmpty, updatedSession.summary == nil {
                updatedSession.summary = finalTranscript
            }
            
            if let index = cachedSessions.firstIndex(where: { $0.id == updatedSession.id }) {
                cachedSessions[index] = updatedSession
            } else {
                cachedSessions.append(updatedSession)
            }
            sortCacheUnlocked()
            try persistCacheUnlocked()
        }
    }
    
    func updateSession(_ session: ListenSession) async throws {
        try await saveSession(session)
    }
    
    func deleteSession(_ sessionId: String) async throws {
        try ensureCacheLoaded()
        try storageQueue.sync {
            cachedSessions.removeAll { $0.id == sessionId }
            try persistCacheUnlocked()
        }
    }
    
    func backfillLegacySegmentsIfNeeded(session: ListenSession) async {
        // No-op for local storage. Sessions already include segments.
    }
    
    func fetchTranscriptText(sessionId: String) async -> String {
        do {
            try ensureCacheLoaded()
        } catch {
            return ""
        }
        
        return storageQueue.sync {
            cachedSessions.first(where: { $0.id == sessionId })?.fullTranscript ?? ""
        }
    }
    
    // MARK: - Private helpers
    
    private func ensureCacheLoaded() throws {
        try storageQueue.sync {
            if !isCacheLoaded {
                try loadCacheUnlocked()
                isCacheLoaded = true
            }
        }
    }
    
    private func loadCacheUnlocked() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            cachedSessions = []
            return
        }
        
        let data = try Data(contentsOf: storageURL)
        let decoded = try decoder.decode([ListenSessionData].self, from: data)
        cachedSessions = decoded.map { $0.toListenSession() }
        sortCacheUnlocked()
    }
    
    private func persistCacheUnlocked() throws {
        let data = try encoder.encode(cachedSessions.map { ListenSessionData(from: $0) })
        try data.write(to: storageURL, options: .atomic)
    }
    
    private func sortCacheUnlocked() {
        cachedSessions.sort { $0.startTime > $1.startTime }
    }
}

