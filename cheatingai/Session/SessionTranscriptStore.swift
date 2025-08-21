import Foundation
import AppKit

@MainActor
final class SessionTranscriptStore: DeepgramSTTDelegate {
    static let shared = SessionTranscriptStore()
    private init() {}
    
    // MARK: - Live Publications
    @Published var lastFinalUtterance: String?
    
    // MARK: - Storage Properties
    private let fileManager = FileManager.default
    private let transcriptsDirectory = "SessionTranscripts"
    private let customDirBookmarkKey = "SessionTranscriptsCustomDirBookmark"
    private var customTranscriptsURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: customDirBookmarkKey) else { return nil }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url
        }
        return nil
    }
    
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
        // Use Application Support to avoid sandbox writes to Documents
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let appDir = base.appendingPathComponent("CheatingAI", isDirectory: true)
        let transcriptsDir = appDir.appendingPathComponent(transcriptsDirectory, isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: transcriptsDir.path) {
            try fileManager.createDirectory(at: transcriptsDir, withIntermediateDirectories: true, attributes: nil)
        }
        return transcriptsDir
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
        
        let transcriptsDir = try getTranscriptsDirectoryWithOverride()
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
            let transcriptsDir = try getTranscriptsDirectoryWithOverride()
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
        
        // Only include actual speech-to-text transcripts from Deepgram STT
        let transcriptSegments = session.segments.filter { 
            $0.source == .server && // Only Deepgram STT results
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSystemAudioHint($0.text)
        }
        
        var content = """
        SESSION TRANSCRIPT
        ==================
        Session ID: \(session.sessionId)
        Start Time: \(formatDate(session.startTime))
        End Time: \(session.endTime.map { formatDate($0) } ?? "In Progress")
        Total Transcript Segments: \(transcriptSegments.count)
        
        """
        
        // Only add summary if there are actual transcripts
        if !transcriptSegments.isEmpty {
            content += """
            SUMMARY
            -------
            \(session.summary ?? "Audio transcription completed")
            
            TRANSCRIPT
            ----------
            
            """
            
            // Add only the actual speech transcripts
            for segment in transcriptSegments {
                content += segment.formattedEntry + "\n"
            }
        } else {
            content += """
            SUMMARY
            -------
            No speech content detected or transcribed.
            
            TRANSCRIPT
            ----------
            No transcript content available.
            
            TROUBLESHOOTING:
            - Check microphone permissions
            - Ensure system audio is playing
            - Verify Deepgram API key is configured
            - Audio may have been silent or too quiet
            """
        }
        
        content += "\nEND OF TRANSCRIPT\n"
        
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
        let transcriptsDir = try getTranscriptsDirectoryWithOverride()
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
            let targetDir = try getTranscriptsDirectoryWithOverride()
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
            let transcriptsDir = try getTranscriptsDirectoryWithOverride()
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
        
        // Only add actual speech content from Deepgram STT
        let cleanedText = deduplicateRealtimeText(text)
        guard !cleanedText.isEmpty else {
            print("🔍 Skipped empty or duplicate transcript")
            return
        }
        
        // Verify this is actual speech content, not system messages
        guard isActualSpeechContent(cleanedText) else {
            print("🔍 Skipped system message: \(cleanedText)")
            return
        }
        
        addTranscriptSegment(text: cleanedText, confidence: 1.0, source: .server)
    }
    
    // ✅ ENHANCED: Real-time deduplication for Deepgram transcripts
    private func deduplicateRealtimeText(_ text: String) -> String {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty text
        guard !cleanedText.isEmpty else { return "" }
        
        // Skip very short utterances (likely noise)
        guard cleanedText.count >= 3 else { return "" }
        
        // Check against recent segments to avoid duplicates
        let recentSegments = transcriptSegments.suffix(10) // Check more segments for better deduplication
        
        for segment in recentSegments {
            let similarity = calculateTextSimilarity(cleanedText, segment.text)
            
            // If 85%+ similar, consider it a duplicate (slightly more strict for Deepgram)
            if similarity > 0.85 {
                print("🔍 Skipped duplicate transcript (similarity: \(String(format: "%.2f", similarity))): \(cleanedText)")
                return ""
            }
        }
        
        // Check for repetitive patterns (e.g., "Thank you for watching" repeated)
        if isRepetitiveContent(cleanedText) {
            print("🔍 Skipped repetitive content: \(cleanedText)")
            return ""
        }
        
        // Check for Deepgram-specific artifacts
        if isDeepgramArtifact(cleanedText) {
            print("🔍 Skipped Deepgram artifact: \(cleanedText)")
            return ""
        }
        
        return cleanedText
    }
    
    // ✅ NEW: Detect Deepgram-specific artifacts that should be filtered
    private func isDeepgramArtifact(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        
        // Common Deepgram artifacts
        let artifacts = [
            "uh",
            "um",
            "ah",
            "eh",
            "oh",
            "hmm",
            "mm",
            "mhm",
            "uh-huh",
            "mm-hmm",
            "you know",
            "like",
            "so",
            "well",
            "actually",
            "basically",
            "literally",
            "i mean",
            "you see",
            "right?",
            "okay?",
            "alright?",
            "..."
        ]
        
        // Check if text is only artifacts
        let words = lowerText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // If all words are artifacts, filter it out
        let nonArtifactWords = words.filter { word in
            !artifacts.contains(word.trimmingCharacters(in: .punctuationCharacters))
        }
        
        // Filter if 80% or more of the words are artifacts
        let artifactRatio = Double(words.count - nonArtifactWords.count) / Double(words.count)
        return artifactRatio >= 0.8
    }
    
    // ✅ NEW: Calculate text similarity using Jaccard similarity
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let words2 = Set(text2.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        guard !words1.isEmpty || !words2.isEmpty else { return 0.0 }
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return Double(intersection.count) / Double(union.count)
    }
    
    // ✅ NEW: Detect repetitive content patterns
    private func isRepetitiveContent(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        
        // Common repetitive phrases
        let repetitivePhrases = [
            "thank you for watching",
            "thanks for watching",
            "please like and subscribe",
            "don't forget to subscribe",
            "hit the like button",
            "comment below",
            "see you next time",
            "until next time",
            "goodbye",
            "bye",
            "end of video",
            "end of stream"
        ]
        
        // Check if text matches any repetitive phrase
        for phrase in repetitivePhrases {
            if lowerText.contains(phrase) {
                return true
            }
        }
        
        // Check for repeated words (e.g., "you you you")
        let words = lowerText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count >= 3 {
            for i in 0..<(words.count - 2) {
                if words[i] == words[i+1] && words[i+1] == words[i+2] {
                    return true
                }
            }
        }
        
        return false
    }
    
    // For final processed transcript
    func addFinalTranscript(_ text: String) {
        addTranscriptSegment(text: text, confidence: 1.0, source: .final)
    }
    
    // ✅ NEW: Check if text is actual speech content vs system message
    private func isActualSpeechContent(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        
        // Skip system messages and metadata
        let systemPatterns = [
            "session summary",
            "duration:",
            "audio capture completed",
            "mock transcript",
            "transcription error",
            "no speech detected",
            "transcription failed"
        ]
        
        for pattern in systemPatterns {
            if lowerText.contains(pattern) {
                return false
            }
        }
        
        // Skip very short or repetitive content
        if text.count < 3 || isRepetitiveContent(text) {
            return false
        }
        
        return true
    }
}

// MARK: - DeepgramSTTDelegate Implementation
extension SessionTranscriptStore {
    nonisolated func didReceiveTranscription(_ text: String, isFinal: Bool, confidence: Float) {
        print("📝 DeepgramSTT: Received transcription: '\(text)' (final: \(isFinal), confidence: \(confidence))")
        
        // Add to transcript segments
        Task { @MainActor in
            // Only process actual speech content
            guard self.isActualSpeechContent(text) else {
                print("🔇 Skipping non-speech content: '\(text)'")
                return
            }
            
            self.addTranscriptSegment(text: text, confidence: confidence, source: .server)
            
            if isFinal {
                print("✅ Added final Deepgram segment: '\(text)'")
                self.lastFinalUtterance = text
            } else {
                print("🔄 Added interim Deepgram segment: '\(text)'")
            }
        }
    }

    // MARK: - Directory Selection
    func chooseTranscriptsDirectory(completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a folder to save session transcripts"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { completion(false); return }
            guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
                completion(false); return
            }
            UserDefaults.standard.set(bookmark, forKey: self?.customDirBookmarkKey ?? "")
            completion(true)
        }
    }

    private func getTranscriptsDirectoryWithOverride() throws -> URL {
        if let customURL = customTranscriptsURL {
            if customURL.startAccessingSecurityScopedResource() {
                defer { customURL.stopAccessingSecurityScopedResource() }
                if !fileManager.fileExists(atPath: customURL.path) {
                    try fileManager.createDirectory(at: customURL, withIntermediateDirectories: true, attributes: nil)
                }
                return customURL
            }
        }
        return try getTranscriptsDirectory()
    }
    
    nonisolated func didReceiveError(_ error: Error) {
        print("❌ DeepgramSTT error: \(error)")
    }
    
    nonisolated func didConnect() {
        print("✅ DeepgramSTT connected")
    }
    
    nonisolated func didDisconnect() {
        print("🔌 DeepgramSTT disconnected")
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

