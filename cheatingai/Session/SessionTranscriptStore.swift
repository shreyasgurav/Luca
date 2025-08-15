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
        // Use the user's actual Documents directory, not the app bundle
        // First try the user's Documents folder directly
        let userDocumentsPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let transcriptsPath = userDocumentsPath.appendingPathComponent(transcriptsDirectory)
        
        // Check if we can write to the user's Documents folder
        if fileManager.isWritableFile(atPath: userDocumentsPath.path) {
            if !fileManager.fileExists(atPath: transcriptsPath.path) {
                try fileManager.createDirectory(at: transcriptsPath, withIntermediateDirectories: true)
                print("📁 Created transcripts directory at: \(transcriptsPath.path)")
            } else {
                print("📁 Using existing transcripts directory at: \(transcriptsPath.path)")
            }
            return transcriptsPath
        } else {
            // Fallback to app's Documents directory if user's Documents is not writable
            let appDocumentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fallbackPath = appDocumentsPath.appendingPathComponent(transcriptsDirectory)
            
            if !fileManager.fileExists(atPath: fallbackPath.path) {
                try fileManager.createDirectory(at: fallbackPath, withIntermediateDirectories: true)
                print("📁 Created fallback transcripts directory at: \(fallbackPath.path)")
            } else {
                print("📁 Using fallback transcripts directory at: \(fallbackPath.path)")
            }
            
            print("⚠️ Using fallback directory - user's Documents folder is not writable")
            return fallbackPath
        }
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
        print("🔍 DEBUG: finishSession called with \(transcriptSegments.count) segments")
        
        guard var session = currentSessionTranscript else {
            print("⚠️ No current session to finish")
            return nil
        }
        
        print("🔍 DEBUG: Current session: \(session.sessionId), started at: \(session.startTime)")
        
        session.endTime = Date()
        session.segments = transcriptSegments
        
        print("🔍 DEBUG: About to save session with \(session.segments.count) segments")
        
        do {
            let savedURL = try await saveSessionTranscript(session)
            print("✅ Session transcript saved: \(savedURL.lastPathComponent)")
            print("✅ Full path: \(savedURL.path)")
            
            // Clean up
            currentSessionTranscript = nil
            transcriptSegments.removeAll()
            
            return savedURL
        } catch {
            print("❌ Failed to save session transcript: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - File Operations
    private func saveSessionTranscript(_ session: SessionTranscript) async throws -> URL {
        print("🔍 DEBUG: saveSessionTranscript called for session: \(session.sessionId)")
        
        let transcriptsDir = try getTranscriptsDirectory()
        print("🔍 DEBUG: Transcripts directory: \(transcriptsDir.path)")
        
        let fileURL = transcriptsDir.appendingPathComponent(session.fileName)
        print("🔍 DEBUG: File will be saved to: \(fileURL.path)")
        
        let content = generateTranscriptContent(for: session)
        print("🔍 DEBUG: Generated content length: \(content.count) characters")
        print("🔍 DEBUG: Content preview: \(content.prefix(200))...")
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        print("🔍 DEBUG: File written successfully")
        
        // Verify the file was created
        if fileManager.fileExists(atPath: fileURL.path) {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            print("🔍 DEBUG: File verified - size: \(fileSize) bytes")
        } else {
            print("❌ DEBUG: File was not created!")
        }
        
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
    
    // MARK: - Migration and Cleanup
    func migrateExistingTranscripts() async {
        print("🔄 Attempting to migrate existing transcripts...")
        
        // Get the sandboxed transcripts directory
        let sandboxDocuments = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sandboxTranscriptsPath = sandboxDocuments.appendingPathComponent(transcriptsDirectory)
        
        guard fileManager.fileExists(atPath: sandboxTranscriptsPath.path) else {
            print("📁 No existing transcripts to migrate")
            return
        }
        
        do {
            let targetDir = try getTranscriptsDirectory()
            let existingFiles = try fileManager.contentsOfDirectory(at: sandboxTranscriptsPath, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "txt" }
            
            print("📁 Found \(existingFiles.count) existing transcripts to migrate")
            
            for fileURL in existingFiles {
                let fileName = fileURL.lastPathComponent
                let targetURL = targetDir.appendingPathComponent(fileName)
                
                // Only copy if target doesn't exist
                if !fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.copyItem(at: fileURL, to: targetURL)
                    print("✅ Migrated: \(fileName)")
                } else {
                    print("⏭️ Skipped (already exists): \(fileName)")
                }
            }
            
            print("✅ Migration completed successfully")
        } catch {
            print("❌ Migration failed: \(error)")
        }
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
    
    func getCurrentSaveLocation() -> String {
        do {
            let transcriptsDir = try getTranscriptsDirectory()
            return transcriptsDir.path
        } catch {
            return "Error: \(error.localizedDescription)"
        }
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
