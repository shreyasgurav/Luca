import Foundation
import AppKit

@MainActor
final class SessionTranscriptStore {
    static let shared = SessionTranscriptStore()
    private init() {}
    
    // MARK: - Storage Properties
    private let fileManager = FileManager.default
    private let transcriptsDirectory = "SessionTranscripts"
    
    // MARK: - Session Transcript Management
    private var currentSessionTranscript: SessionTranscript?
    private var transcriptSegments: [TranscriptSegment] = []
    
    // MARK: - Dashboard Integration
    @Published var sessions: [TranscriptSession] = []
    
    struct SessionTranscript {
        let sessionId: String
        let startTime: Date
        var endTime: Date?
        var segments: [TranscriptSegment]
        var fileName: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return "transcript_\(formatter.string(from: startTime))_\(sessionId.prefix(8)).txt"
        }
    }
    
    struct TranscriptSegment {
        let timestamp: Date
        let text: String
        let confidence: Float
        let source: TranscriptSource
        
        enum TranscriptSource {
            case local      // Apple Speech (SpeechTranscriber)
            case server     // Backend transcription
            case final      // Final processed transcript
        }
        
        var formattedEntry: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeStr = formatter.string(from: timestamp)
            let sourceTag = source == .local ? "[L]" : source == .server ? "[S]" : "[F]"
            return "[\(timeStr)] \(sourceTag) \(text)"
        }
    }
    
    // MARK: - Directory Setup
    private func getTranscriptsDirectory() throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let transcriptsPath = documentsPath.appendingPathComponent(transcriptsDirectory)
        
        if !fileManager.fileExists(atPath: transcriptsPath.path) {
            try fileManager.createDirectory(at: transcriptsPath, withIntermediateDirectories: true)
        }
        
        return transcriptsPath
    }
    
    // MARK: - Session Lifecycle
    func startSession(sessionId: String) {
        print("📝 SessionTranscriptStore: Starting session \(sessionId)")
        
        currentSessionTranscript = SessionTranscript(
            sessionId: sessionId,
            startTime: Date(),
            endTime: nil,
            segments: []
        )
        transcriptSegments.removeAll()
    }
    
    func addTranscriptSegment(text: String, confidence: Float = 1.0, source: TranscriptSegment.TranscriptSource = .local) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let segment = TranscriptSegment(
            timestamp: Date(),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence,
            source: source
        )
        
        transcriptSegments.append(segment)
        currentSessionTranscript?.segments = transcriptSegments
        
        print("📝 Added transcript segment: \(text.prefix(50))...")
        
        // Auto-save every 10 segments to prevent data loss
        if transcriptSegments.count % 10 == 0 {
            Task { await autoSaveCurrentSession() }
        }
    }
    
    func finishSession() async -> URL? {
        guard var session = currentSessionTranscript else {
            print("⚠️ No current session to finish")
            return nil
        }
        
        session.endTime = Date()
        session.segments = transcriptSegments
        
        do {
            let savedURL = try await saveSessionTranscript(session)
            print("✅ Session transcript saved: \(savedURL.lastPathComponent)")
            
            // Clean up
            currentSessionTranscript = nil
            transcriptSegments.removeAll()
            
            return savedURL
        } catch {
            print("❌ Failed to save session transcript: \(error)")
            return nil
        }
    }
    
    // MARK: - File Operations
    private func saveSessionTranscript(_ session: SessionTranscript) async throws -> URL {
        let transcriptsDir = try getTranscriptsDirectory()
        let fileURL = transcriptsDir.appendingPathComponent(session.fileName)
        
        let content = generateTranscriptContent(for: session)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    private func autoSaveCurrentSession() async {
        guard let session = currentSessionTranscript else { return }
        
        do {
            let transcriptsDir = try getTranscriptsDirectory()
            let tempFileName = "temp_\(session.fileName)"
            let tempFileURL = transcriptsDir.appendingPathComponent(tempFileName)
            
            let content = generateTranscriptContent(for: session)
            try content.write(to: tempFileURL, atomically: true, encoding: .utf8)
            
            print("💾 Auto-saved session transcript")
        } catch {
            print("⚠️ Auto-save failed: \(error)")
        }
    }
    
    private func generateTranscriptContent(for session: SessionTranscript) -> String {
        var content = """
        SESSION TRANSCRIPT
        ==================
        Session ID: \(session.sessionId)
        Start Time: \(formatDate(session.startTime))
        End Time: \(session.endTime.map { formatDate($0) } ?? "In Progress")
        Total Segments: \(session.segments.count)
        
        TRANSCRIPT
        ----------
        
        """
        
        for segment in session.segments {
            content += segment.formattedEntry + "\n"
        }
        
        content += "\n\nEND OF TRANSCRIPT\n"
        return content
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    // MARK: - Public Interface for Integration
    func getAllTranscripts() throws -> [URL] {
        let transcriptsDir = try getTranscriptsDirectory()
        return try fileManager.contentsOfDirectory(at: transcriptsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" && $0.lastPathComponent.hasPrefix("transcript_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // Most recent first
    }
    
    func deleteTranscript(at url: URL) throws {
        try fileManager.removeItem(at: url)
        print("🗑️ Deleted transcript: \(url.lastPathComponent)")
    }
    
    func getCurrentSessionInfo() -> (sessionId: String?, segmentCount: Int, isActive: Bool) {
        return (
            sessionId: currentSessionTranscript?.sessionId,
            segmentCount: transcriptSegments.count,
            isActive: currentSessionTranscript != nil
        )
    }
}

// MARK: - Integration Extensions
extension SessionTranscriptStore {
    // For SpeechTranscriber integration
    func addLocalTranscript(_ text: String, confidence: Float = 1.0) {
        addTranscriptSegment(text: text, confidence: confidence, source: .local)
    }
    
    // For server transcript integration  
    func addServerTranscript(_ text: String) {
        addTranscriptSegment(text: text, confidence: 1.0, source: .server)
    }
    
    // For final processed transcript
    func addFinalTranscript(_ text: String) {
        addTranscriptSegment(text: text, confidence: 1.0, source: .final)
    }
}

// MARK: - Dashboard Integration
extension SessionTranscriptStore: ObservableObject {
    struct TranscriptSession: Identifiable {
        let id: String
        let createdAt: Date
        let sizeBytes: Int
        let preview: String
        let fileURL: URL
    }
    
    func loadSessions() async {
        do {
            let transcriptURLs = try getAllTranscripts()
            sessions = transcriptURLs.compactMap { url in
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let fileSize = attributes[.size] as? Int,
                      let creationDate = attributes[.creationDate] as? Date else {
                    return nil
                }
                
                let preview = try? String(contentsOf: url, encoding: .utf8)
                    .components(separatedBy: .newlines)
                    .prefix(3)
                    .joined(separator: " ")
                    .prefix(100)
                    .description
                
                return TranscriptSession(
                    id: url.lastPathComponent.replacingOccurrences(of: ".txt", with: ""),
                    createdAt: creationDate,
                    sizeBytes: fileSize,
                    preview: preview ?? "No preview available",
                    fileURL: url
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("❌ Error loading sessions: \(error)")
            sessions = []
        }
    }
    
    func revealInFinder(_ session: TranscriptSession) {
        NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
    }
    
    func delete(_ session: TranscriptSession) {
        do {
            try deleteTranscript(at: session.fileURL)
            Task { await loadSessions() }
        } catch {
            print("❌ Error deleting session: \(error)")
        }
    }
}
