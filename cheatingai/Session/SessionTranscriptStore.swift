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
        var summary: String? // NEW: model summary
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
        print("🔍 DEBUG: getTranscriptsDirectory called")
        
        // Try to get the REAL user's Documents folder using system APIs
        let realUserDocuments = getRealUserDocumentsFolder()
        print("🔍 DEBUG: Real user Documents path: \(realUserDocuments.path)")
        
        // Check if this is NOT the sandboxed container
        if !realUserDocuments.path.contains("Library/Containers") {
            print("✅ Found real user Documents folder, not sandboxed")
            
            let userTranscriptsPath = realUserDocuments.appendingPathComponent(transcriptsDirectory)
            print("🔍 DEBUG: User transcripts path: \(userTranscriptsPath.path)")
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: userTranscriptsPath.path) {
                print("🔍 DEBUG: User transcripts directory doesn't exist, creating...")
                do {
                    try fileManager.createDirectory(at: userTranscriptsPath, withIntermediateDirectories: true, attributes: nil)
                    print("📁 Created user transcripts directory at: \(userTranscriptsPath.path)")
                } catch {
                    print("⚠️ Failed to create user transcripts directory: \(error.localizedDescription)")
                }
            } else {
                print("📁 Using existing user transcripts directory at: \(userTranscriptsPath.path)")
            }
            
            // Test write access to user's Documents folder
            let testFile = userTranscriptsPath.appendingPathComponent(".user_test")
            print("🔍 DEBUG: Testing write access to real user Documents: \(testFile.path)")
            
            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                print("🔍 DEBUG: Real user Documents write test successful")
                try fileManager.removeItem(at: testFile)
                print("🔍 DEBUG: Real user Documents test file removed")
                print("✅ Using real user's Documents folder")
                return userTranscriptsPath
            } catch {
                print("⚠️ Cannot write to real user's Documents folder: \(error.localizedDescription)")
                print("🔄 Falling back to other locations...")
            }
        } else {
            print("⚠️ Real user Documents path is still sandboxed, trying alternatives...")
        }
        
        // Fallback locations - prioritize Downloads folder (usually has fewer restrictions)
        let fallbackLocations = [
            ("User Downloads", getRealUserDownloadsFolder()),
            ("User Desktop", getRealUserDesktopFolder()),
            ("App Documents", fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!)
        ]
        
        for (locationName, basePath) in fallbackLocations {
            let transcriptsPath = basePath.appendingPathComponent(transcriptsDirectory)
            print("🔍 DEBUG: Trying fallback \(locationName): \(transcriptsPath.path)")
            
            // Skip if this is the sandboxed container (we want the real user folder)
            if transcriptsPath.path.contains("Library/Containers") && locationName != "App Documents" {
                print("⚠️ Skipping sandboxed container: \(transcriptsPath.path)")
                continue
            }
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: transcriptsPath.path) {
                print("🔍 DEBUG: Fallback transcripts directory doesn't exist, creating...")
                do {
                    try fileManager.createDirectory(at: transcriptsPath, withIntermediateDirectories: true, attributes: nil)
                    print("📁 Created fallback transcripts directory at: \(transcriptsPath.path)")
                } catch {
                    print("⚠️ Failed to create fallback directory at \(locationName): \(error.localizedDescription)")
                    continue
                }
            } else {
                print("📁 Using existing fallback transcripts directory at: \(transcriptsPath.path)")
            }
            
            // Verify we can write to this directory
            let testFile = transcriptsPath.appendingPathComponent(".fallback_test")
            print("🔍 DEBUG: Testing fallback write access: \(testFile.path)")
            
            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                print("🔍 DEBUG: Fallback write test successful")
                try fileManager.removeItem(at: testFile)
                print("🔍 DEBUG: Fallback test file removed")
                print("✅ Using fallback location: \(locationName)")
                return transcriptsPath
            } catch {
                print("⚠️ Cannot write to fallback \(locationName): \(error.localizedDescription)")
                continue
            }
        }
        
        // Last resort: app's Documents directory
        print("❌ All locations failed, using app's Documents directory as last resort")
        let appDocumentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let lastResortPath = appDocumentsPath.appendingPathComponent(transcriptsDirectory)
        
        if !fileManager.fileExists(atPath: lastResortPath.path) {
            try fileManager.createDirectory(at: lastResortPath, withIntermediateDirectories: true, attributes: nil)
            print("📁 Created last resort transcripts directory at: \(lastResortPath.path)")
        }
        
        return lastResortPath
    }
    
    // MARK: - Real User Directory Access
    private func getRealUserDocumentsFolder() -> URL {
        // Try multiple methods to get the real user Documents folder
        
        // Method 1: Use NSHomeDirectory() which might bypass some sandbox restrictions
        let nsHomeDir = NSHomeDirectory()
        let nsDocuments = (nsHomeDir as NSString).appendingPathComponent("Documents")
        print("🔍 DEBUG: NSHomeDirectory Documents: \(nsDocuments)")
        
        if !nsDocuments.contains("Library/Containers") {
            print("✅ NSHomeDirectory found real user Documents")
            return URL(fileURLWithPath: nsDocuments)
        }
        
        // Method 2: Try to construct from /Users/username
        let username = NSUserName()
        let userDocuments = "/Users/\(username)/Documents"
        print("🔍 DEBUG: Constructed user Documents: \(userDocuments)")
        
        if fileManager.fileExists(atPath: userDocuments) {
            print("✅ Constructed path found real user Documents")
            return URL(fileURLWithPath: userDocuments)
        }
        
        // Method 3: Try to get from environment variables
        if let homeEnv = ProcessInfo.processInfo.environment["HOME"] {
            let envDocuments = (homeEnv as NSString).appendingPathComponent("Documents")
            print("🔍 DEBUG: Environment HOME Documents: \(envDocuments)")
            
            if !envDocuments.contains("Library/Containers") && fileManager.fileExists(atPath: envDocuments) {
                print("✅ Environment HOME found real user Documents")
                return URL(fileURLWithPath: envDocuments)
            }
        }
        
        // Method 4: Try to access via shell command (last resort)
        let shellDocuments = getDocumentsViaShell()
        if !shellDocuments.isEmpty && !shellDocuments.contains("Library/Containers") {
            print("✅ Shell command found real user Documents: \(shellDocuments)")
            return URL(fileURLWithPath: shellDocuments)
        }
        
        // If all methods fail, return the sandboxed path
        print("⚠️ All methods failed, returning sandboxed path")
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }
    
    private func getRealUserDownloadsFolder() -> URL {
        // Try to get the Downloads folder for the real user
        let username = NSUserName()
        let userDownloads = "/Users/\(username)/Downloads"
        
        if fileManager.fileExists(atPath: userDownloads) {
            print("✅ Found real user Downloads: \(userDownloads)")
            return URL(fileURLWithPath: userDownloads)
        }
        
        // Fallback to sandboxed path
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
    
    private func getRealUserDesktopFolder() -> URL {
        // Similar logic for Desktop folder
        let username = NSUserName()
        let userDesktop = "/Users/\(username)/Desktop"
        
        if fileManager.fileExists(atPath: userDesktop) {
            print("✅ Found real user Desktop: \(userDesktop)")
            return URL(fileURLWithPath: userDesktop)
        }
        
        // Fallback to sandboxed path
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
    
    private func getDocumentsViaShell() -> String {
        // Try to get Documents folder via shell command
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "echo $HOME/Documents"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output
            }
        } catch {
            print("⚠️ Shell command failed: \(error.localizedDescription)")
        }
        
        return ""
    }
    
    // MARK: - Session Lifecycle
    func startSession(sessionId: String) {
        print("📝 SessionTranscriptStore: Starting session \(sessionId)")
        print("🔍 DEBUG: Previous session: \(currentSessionTranscript?.sessionId ?? "NIL")")
        print("🔍 DEBUG: Previous segments count: \(transcriptSegments.count)")
        
        currentSessionTranscript = SessionTranscript(
            sessionId: sessionId,
            startTime: Date(),
            endTime: nil,
            segments: [],
            summary: nil
        )
        transcriptSegments.removeAll()
        
        print("🔍 DEBUG: New session created: \(currentSessionTranscript?.sessionId ?? "NIL")")
        print("🔍 DEBUG: Segments cleared, new count: \(transcriptSegments.count)")
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
        print("🔍 DEBUG: Current session: \(currentSessionTranscript?.sessionId ?? "NIL")")
        print("🔍 DEBUG: Total segments: \(transcriptSegments.count)")
        
        // Auto-save every 10 segments to prevent data loss
        if transcriptSegments.count % 10 == 0 {
            Task { await autoSaveCurrentSession() }
        }
    }
    
    func finishSession() async -> URL? {
        print("🔍 DEBUG: finishSession called with \(transcriptSegments.count) segments")
        print("🔍 DEBUG: Current session transcript: \(currentSessionTranscript?.sessionId ?? "NIL")")
        print("🔍 DEBUG: Transcript segments array: \(transcriptSegments.count) segments")
        
        guard var session = currentSessionTranscript else {
            print("⚠️ No current session to finish")
            return nil
        }
        
        print("🔍 DEBUG: Current session: \(session.sessionId), started at: \(session.startTime)")
        print("🔍 DEBUG: Session has \(session.segments.count) segments")
        
        session.endTime = Date()
        session.segments = transcriptSegments
        
        print("🔍 DEBUG: About to save session with \(session.segments.count) segments")
        print("🔍 DEBUG: Session duration: \(session.endTime!.timeIntervalSince(session.startTime)) seconds")
        
        do {
            // Generate summary before saving
            let fullText = generateTranscriptContent(for: session)
            let summaryText = try? await SummaryManager.shared.generateSummary(from: fullText)
            session.summary = summaryText
            
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
        print("🔍 DEBUG: Session has \(session.segments.count) segments")
        
        let transcriptsDir = try getTranscriptsDirectory()
        print("🔍 DEBUG: Transcripts directory: \(transcriptsDir.path)")
        
        let fileURL = transcriptsDir.appendingPathComponent(session.fileName)
        print("🔍 DEBUG: File will be saved to: \(fileURL.path)")
        
        let content = generateTranscriptContent(for: session)
        print("🔍 DEBUG: Generated content length: \(content.count) characters")
        print("🔍 DEBUG: Content preview: \(content.prefix(200))...")
        
        print("🔍 DEBUG: Attempting to write file...")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        print("🔍 DEBUG: File written successfully")
        
        // Verify the file was created
        if fileManager.fileExists(atPath: fileURL.path) {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            print("🔍 DEBUG: File verified - size: \(fileSize) bytes")
            print("🔍 DEBUG: File attributes: \(attributes)")
            print("✅ SUCCESS: Transcript file saved to: \(fileURL.path)")
        } else {
            print("❌ DEBUG: File was not created!")
            print("❌ DEBUG: File path: \(fileURL.path)")
            print("❌ DEBUG: Directory exists: \(fileManager.fileExists(atPath: transcriptsDir.path))")
            print("❌ DEBUG: Directory contents: \(try? fileManager.contentsOfDirectory(at: transcriptsDir, includingPropertiesForKeys: nil))")
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
    
    private func isSystemAudioHint(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("[no system audio detected]") { return true }
        if lower.contains("to capture youtube/zoom") { return true }
        if lower.contains("blackhole") { return true }
        return false
    }
    
    private func generateTranscriptContent(for session: SessionTranscript) -> String {
        print("🔍 DEBUG: generateTranscriptContent called for session: \(session.sessionId)")
        print("🔍 DEBUG: Session has \(session.segments.count) segments")
        
        // Filter out any guidance/hint segments before exporting
        let exportSegments = session.segments.filter { !isSystemAudioHint($0.text) }
        
        var content = """
        SESSION TRANSCRIPT
        ==================
        Session ID: \(session.sessionId)
        Start Time: \(formatDate(session.startTime))
        End Time: \(session.endTime.map { formatDate($0) } ?? "In Progress")
        Total Segments: \(exportSegments.count)
        
        SUMMARY
        -------
        \(session.summary ?? "(Summary not available)")
        
        TRANSCRIPT
        ----------
        
        """
        
        for (index, segment) in exportSegments.enumerated() {
            content += segment.formattedEntry + "\n"
            print("🔍 DEBUG: Added segment \(index + 1): \(segment.formattedEntry)")
        }
        
        content += "\n\nEND OF TRANSCRIPT\n"
        
        print("🔍 DEBUG: Generated content length: \(content.count) characters")
        print("🔍 DEBUG: Content preview: \(content.prefix(200))...")
        
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
    
    func testWriteAccess() -> Bool {
        do {
            let transcriptsDir = try getTranscriptsDirectory()
            let testFile = transcriptsDir.appendingPathComponent(".write_test")
            
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            
            print("✅ Write access test successful at: \(transcriptsDir.path)")
            return true
        } catch {
            print("❌ Write access test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func forceUseUserDocuments() -> String {
        print("🔄 Force using user's actual Documents folder...")
        
        let userDocumentsPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let transcriptsPath = userDocumentsPath.appendingPathComponent(transcriptsDirectory)
        
        print("🔍 DEBUG: User Documents path: \(userDocumentsPath.path)")
        print("🔍 DEBUG: Target transcripts path: \(transcriptsPath.path)")
        
        do {
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: transcriptsPath.path) {
                try fileManager.createDirectory(at: transcriptsPath, withIntermediateDirectories: true, attributes: nil)
                print("📁 Created transcripts directory at: \(transcriptsPath.path)")
            }
            
            // Test write access
            let testFile = transcriptsPath.appendingPathComponent(".force_test")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            
            print("✅ Force write test successful at: \(transcriptsPath.path)")
            return transcriptsPath.path
        } catch {
            print("❌ Force write test failed: \(error.localizedDescription)")
            return "Error: \(error.localizedDescription)"
        }
    }
    
    func checkAppPermissions() -> String {
        print("🔍 Checking app permissions and sandbox status...")
        
        var status = "App Permission Check:\n"
        
        // Check if we're in a sandbox
        let isSandboxed = Bundle.main.appStoreReceiptURL != nil
        status += "• Sandboxed: \(isSandboxed ? "YES" : "NO")\n"
        
        // Check home directory access
        let homeDir = fileManager.homeDirectoryForCurrentUser
        status += "• Home directory: \(homeDir.path)\n"
        
        // Check if home directory contains "Containers" (sandboxed)
        let isHomeSandboxed = homeDir.path.contains("Library/Containers")
        status += "• Home directory sandboxed: \(isHomeSandboxed ? "YES" : "NO")\n"
        
        // Check Documents directory access
        let userDocs = homeDir.appendingPathComponent("Documents")
        status += "• User Documents: \(userDocs.path)\n"
        
        // Check if Documents is writable
        let isDocsWritable = fileManager.isWritableFile(atPath: userDocs.path)
        status += "• User Documents writable: \(isDocsWritable ? "YES" : "NO")\n"
        
        // Check app's Documents directory
        if let appDocs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            status += "• App Documents: \(appDocs.path)\n"
            let isAppDocsWritable = fileManager.isWritableFile(atPath: appDocs.path)
            status += "• App Documents writable: \(isAppDocsWritable ? "YES" : "NO")\n"
        }
        
        print(status)
        return status
    }
    
    func testRealUserDirectoryAccess() -> String {
        print("🔍 Testing real user directory access methods...")
        
        var results = "Real User Directory Access Test:\n"
        
        // Test NSHomeDirectory
        let nsHomeDir = NSHomeDirectory()
        let nsDocuments = (nsHomeDir as NSString).appendingPathComponent("Documents")
        let nsHomeSandboxed = nsDocuments.contains("Library/Containers")
        results += "• NSHomeDirectory: \(nsDocuments) (Sandboxed: \(nsHomeSandboxed ? "YES" : "NO"))\n"
        
        // Test constructed path
        let username = NSUserName()
        let constructedDocs = "/Users/\(username)/Documents"
        let constructedExists = fileManager.fileExists(atPath: constructedDocs)
        results += "• Constructed path: \(constructedDocs) (Exists: \(constructedExists ? "YES" : "NO"))\n"
        
        // Test environment variable
        if let homeEnv = ProcessInfo.processInfo.environment["HOME"] {
            let envDocs = (homeEnv as NSString).appendingPathComponent("Documents")
            let envSandboxed = envDocs.contains("Library/Containers")
            results += "• Environment HOME: \(envDocs) (Sandboxed: \(envSandboxed ? "YES" : "NO"))\n"
        } else {
            results += "• Environment HOME: Not found\n"
        }
        
        // Test shell command
        let shellDocs = getDocumentsViaShell()
        let shellSandboxed = shellDocs.contains("Library/Containers")
        results += "• Shell command: \(shellDocs.isEmpty ? "Failed" : shellDocs) (Sandboxed: \(shellSandboxed ? "YES" : "NO"))\n"
        
        // Test our new method
        let realDocs = getRealUserDocumentsFolder()
        let realSandboxed = realDocs.path.contains("Library/Containers")
        results += "• Our method result: \(realDocs.path) (Sandboxed: \(realSandboxed ? "YES" : "NO"))\n"
        
        print(results)
        return results
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
        print("🔍 DEBUG: addServerTranscript called with text: \(text.prefix(50))...")
        print("🔍 DEBUG: Current session: \(currentSessionTranscript?.sessionId ?? "NIL")")
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
