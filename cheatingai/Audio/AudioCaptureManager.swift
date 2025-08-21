import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit
import CoreGraphics
import Combine
import os.log

// MARK: - Audio Quality Models

struct AudioQuality {
    let silenceRatio: Float      // 0.0 = no silence, 1.0 = all silence
    let dynamicRange: Float      // Dynamic range in dB
    let clippingRate: Float      // 0.0 = no clipping, 1.0 = all clipped
    let isAcceptable: Bool       // Overall quality assessment
}

@MainActor
final class AudioCaptureManager: NSObject, ObservableObject {
    static let shared = AudioCaptureManager()

    // MARK: - Published Properties for UI
    @Published var isListening = false
    @Published var liveTranscript = ""
    @Published var connectionStatus = "Ready"
    
    // MARK: - Debug Properties
    @Published var isAudioFlowing = false
    @Published var audioLevelDebug: Float = 0.0
    @Published var lastAudioTimestamp: Date?
    private let logger = Logger(subsystem: "com.cheating.cheatingai", category: "AudioCapture")

    // MARK: - Professional Audio Capture Properties
    private var screenCaptureSession: SCStream?
    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    // ScreenCaptureKit → Deepgram conversion
    private var scInputFormat: AVAudioFormat?
    private let dgTargetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!
    private var scToDgConverter: AVAudioConverter?
    
    // MARK: - Deepgram STT Integration
    private let deepgramSTT = DeepgramSTT()
    private var cancellables = Set<AnyCancellable>()
    
    // Audio processing
    private var accumulatingPCM = Data()
    private var accumulatedSamples: Int = 0
    private let targetSampleRate: Double = 16_000
    private let chunkSizeBytes = DeepgramConfig.chunkSizeBytes // 50ms chunks for real-time
    private var samplesPerChunk: Int { chunkSizeBytes / 2 } // 16-bit samples
    
    // Session management
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var isRunning = false
    private var finalizedSegments: [SessionTranscriptStore.TranscriptSegment] = []
    private var debugBufferCount: Int = 0
    private var lastNonSilenceAt: Date = Date()
    private var lastVoiceActivity: Date = Date()
    
    // VAD Configuration
    private let voiceThreshold: Float = 0.01
    private let maxChunkDuration: Double = 10.0
    
    // Screen recording permission
    private var hasScreenRecordingPermission = false
    
    // Legacy WebSocket support (for backward compatibility)
    private var useWebSocket = false // Disabled in favor of Deepgram
    private var webSocketTranscript = ""

    // MARK: - Initialization
    
    override init() {
        super.init()
        setupDeepgramIntegration()
    }
    
    // MARK: - Public Interface
    
    /// Start listening with Deepgram STT
    func startListening(sessionId: String? = nil, onStarted: @escaping (Bool) -> Void) {
        guard !isListening else { onStarted(true); return }
        
        let sessionId = sessionId ?? UUID().uuidString
        self.sessionId = sessionId
        self.sessionStartTime = Date()
        
        Task {
            do {
                connectionStatus = "Connecting to Deepgram..."
                
                // Connect to Deepgram first
                deepgramSTT.connect()
                
                connectionStatus = "Starting audio capture..."
                
                // Start system audio capture
                try await startScreenCaptureWithAudio()
                
                isListening = true
                connectionStatus = "Listening..."
                
                // Start session in transcript store
        SessionTranscriptStore.shared.startSession(sessionId: sessionId)
                
                onStarted(true)
                print("✅ Nova: Started listening with Deepgram STT")
                
            } catch {
                connectionStatus = "Error: \(error.localizedDescription)"
                onStarted(false)
                print("❌ Nova: Failed to start listening: \(error)")
            }
        }
    }
    
    /// Stop listening and save transcript
    func stopListening() async {
        guard isListening else { return }
        
        connectionStatus = "Stopping..."
        
        // Stop audio capture
        await stopScreenCapture()
        
        // Finalize Deepgram connection
        deepgramSTT.finalizeAndDisconnect()
        
        // Save transcript
        await finishSession()
        
        isListening = false
        connectionStatus = "Ready"
        
        print("✅ Nova: Stopped listening")
    }
    
    // MARK: - Legacy Interface (for backward compatibility)
    
    func startListening(sessionId: String, onStarted: @escaping (Bool) -> Void) {
        startListening(sessionId: sessionId as String?, onStarted: onStarted)
    }
    
    // MARK: - Deepgram Integration
    
    private func setupDeepgramIntegration() {
        // Set the delegate to SessionTranscriptStore for transcript handling
        deepgramSTT.delegate = SessionTranscriptStore.shared
        
        // Update connection status when Deepgram connects/disconnects
        deepgramSTT.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, on: self)
            .store(in: &cancellables)
        
        // Update live transcript from Deepgram
        deepgramSTT.$lastTranscription
            .receive(on: DispatchQueue.main)
            .assign(to: \.liveTranscript, on: self)
            .store(in: &cancellables)
    }
    
    // ✅ NEW: Store transcript content in vector memory system
    private func storeTranscriptInMemory(_ transcript: String) async {
        // Only store substantial content (not filler words or short phrases)
        guard transcript.count > 10 else { return }
        
        // Determine memory type based on content analysis
        let memoryType = analyzeTranscriptType(transcript)
        let importance = calculateTranscriptImportance(transcript)
        
        // Store in vector memory if it seems important enough
        if importance > 0.5 {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: transcript,
                type: memoryType,
                source: .conversation,
                importance: importance
            )
            
            print("💾 Stored transcript in memory: \(transcript.prefix(50))...")
        }
    }
    
    // ✅ NEW: Analyze transcript to determine memory type
    private func analyzeTranscriptType(_ transcript: String) -> MemoryType {
        let lowerText = transcript.lowercased()
        
        // Check for specific patterns
        if lowerText.contains("i like") || lowerText.contains("i prefer") || lowerText.contains("i love") {
            return .preference
        } else if lowerText.contains("my name") || lowerText.contains("i am") || lowerText.contains("i'm") {
            return .personal
        } else if lowerText.contains("work") || lowerText.contains("job") || lowerText.contains("company") {
            return .professional
        } else if lowerText.contains("want to") || lowerText.contains("plan to") || lowerText.contains("goal") {
            return .goal
        } else if lowerText.contains("remember") || lowerText.contains("always") || lowerText.contains("never") {
            return .instruction
        } else if lowerText.contains("friend") || lowerText.contains("family") || lowerText.contains("relationship") {
            return .relationship
        } else {
            return .knowledge
        }
    }
    
    // ✅ NEW: Calculate importance score for transcript content
    private func calculateTranscriptImportance(_ transcript: String) -> Double {
        let lowerText = transcript.lowercased()
        var importance: Double = 0.3 // Base importance
        
        // Boost importance for personal information
        if lowerText.contains("my name") || lowerText.contains("i am") {
            importance += 0.4
        }
        
        // Boost for preferences
        if lowerText.contains("i like") || lowerText.contains("i prefer") || lowerText.contains("favorite") {
            importance += 0.3
        }
        
        // Boost for goals and plans
        if lowerText.contains("want to") || lowerText.contains("plan to") || lowerText.contains("goal") {
            importance += 0.3
        }
        
        // Boost for work/professional content
        if lowerText.contains("work") || lowerText.contains("job") || lowerText.contains("career") {
            importance += 0.2
        }
        
        // Boost for instructions
        if lowerText.contains("remember") || lowerText.contains("always") || lowerText.contains("never") {
            importance += 0.4
        }
        
        // Penalize for very short content
        if transcript.count < 20 {
            importance -= 0.2
        }
        
        // Penalize for filler words
        let fillerWords = ["um", "uh", "like", "you know", "basically", "literally"]
        let words = lowerText.components(separatedBy: .whitespacesAndNewlines)
        let fillerCount = words.filter { word in
            fillerWords.contains(word.trimmingCharacters(in: .punctuationCharacters))
        }.count
        
        if Double(fillerCount) / Double(words.count) > 0.3 {
            importance -= 0.3
        }
        
        return max(0.0, min(1.0, importance))
    }
    

    
    // MARK: - Session Management
    
    private func finishSession() async {
        guard let sessionId = sessionId,
              let _ = sessionStartTime else { return }
        
        // Finalize session in transcript store
        let transcriptURL = await SessionTranscriptStore.shared.finishSession()
        
        // Clear session data
        self.sessionId = nil
        self.sessionStartTime = nil
        finalizedSegments.removeAll()
        accumulatingPCM.removeAll()
        accumulatedSamples = 0
        
        print("✅ Session \(sessionId) completed. Transcript saved: \(transcriptURL?.lastPathComponent ?? "unknown")")
    }
    
    // MARK: - Audio Capture (Enhanced for Deepgram)
    
    private func startScreenCaptureWithAudio() async throws {
        logger.info("🎬 Starting audio capture...")
        
        // Get available content for screen + audio capture
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = availableContent.displays.first else {
            logger.error("❌ No display available for capture")
            throw AudioCaptureError.noDisplayAvailable
        }
        
        logger.info("🖥️ Display: \(display.width)x\(display.height)")
        
        // Check system audio devices
        let audioDevices = AVCaptureDevice.devices(for: .audio)
        logger.info("🎤 Available audio devices: \(audioDevices.count)")
        
        for device in audioDevices {
            logger.info("📱 Device: \(device.localizedName) - ID: \(device.uniqueID)")
        }
        
        // Log which applications can provide audio
        for app in availableContent.applications {
            logger.info("📱 App: \(app.applicationName) - Bundle: \(app.bundleIdentifier) - Process ID: \(app.processID)")
        }
        
        // Configure stream for screen + audio capture
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.capturesAudio = true  // This captures system audio!
        configuration.sampleRate = Int(targetSampleRate)
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true  // Don't capture Nova's own audio
        
        logger.info("⚙️ Stream configuration - Audio: \(configuration.capturesAudio), Sample Rate: \(configuration.sampleRate), Channels: \(configuration.channelCount)")
        
        // Create and start the capture stream
        screenCaptureSession = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        // Add audio stream output
        try screenCaptureSession?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        // Attach a screen output to suppress ScreenCaptureKit warnings even if we ignore frames
        try? screenCaptureSession?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        
        // Start capture
        try await screenCaptureSession?.startCapture()
        
        // Start audio flow monitoring
        checkAudioFlow()
        
        logger.info("✅ System audio capture started for Deepgram STT")
        print("✅ System audio capture started for Deepgram STT")
    }
    
    // MARK: - Audio Flow Monitoring
    
    private func checkAudioFlow() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if let lastTimestamp = self.lastAudioTimestamp {
                let timeSinceLastAudio = Date().timeIntervalSince(lastTimestamp)
                if timeSinceLastAudio > 3.0 {
                    self.logger.warning("⚠️ No audio received for \(String(format: "%.1f", timeSinceLastAudio)) seconds")
                    DispatchQueue.main.async {
                        self.isAudioFlowing = false
                    }
                }
            } else {
                self.logger.warning("⚠️ No audio has been received yet")
                DispatchQueue.main.async {
                    self.isAudioFlowing = false
                }
            }
        }
    }
    
    private func stopScreenCapture() async {
        guard let session = screenCaptureSession else { return }
        
        do {
            try await session.stopCapture()
            screenCaptureSession = nil
            print("✅ System audio capture stopped")
        } catch {
            print("⚠️ Error stopping screen capture: \(error)")
        }
    }
    
    private func setupWebSocket() {
        // Configure WebSocket callbacks
        ListenAPI.shared.onTranscriptionUpdate = { [weak self] text, fullTranscript in
            DispatchQueue.main.async {
                self?.webSocketTranscript = fullTranscript
                // Add server transcript to session store
                SessionTranscriptStore.shared.addServerTranscript(text)
                print("🔌 WebSocket transcript: \(text)")
            }
        }
        
        ListenAPI.shared.onSessionStarted = { [weak self] sid in
            DispatchQueue.main.async {
                self?.sessionId = sid
                print("✅ WebSocket session started: \(sid)")
            }
        }
        
        ListenAPI.shared.onSessionCompleted = { [weak self] finalTranscript, stats in
            DispatchQueue.main.async {
                // Final server transcript
                SessionTranscriptStore.shared.addServerTranscript(finalTranscript)
                print("✅ WebSocket session completed: \(finalTranscript.count) chars")
            }
        }
        
        ListenAPI.shared.onSessionFinished = { [weak self] in
            DispatchQueue.main.async {
                // NEW: Finish the session and save transcript to disk
                Task {
                    await self?.finishSession()
                }
                print("🔌 WebSocket session finished, transcript saved")
            }
        }
        
        ListenAPI.shared.onError = { error in
            print("❌ WebSocket error: \(error)")
            // Fallback to HTTP if WebSocket fails
            DispatchQueue.main.async {
                self.useWebSocket = false
            }
        }
        
        // Connect and start WebSocket session
        ListenAPI.shared.connect()
        ListenAPI.shared.startSession()
    }
    
    private func checkScreenRecordingPermission() async -> Bool {
        // Check current permission status
        let currentStatus = checkCurrentScreenRecordingStatus()
        if currentStatus {
            hasScreenRecordingPermission = true
            return true
        }
        
        // Request permission
        let granted = await requestScreenRecordingPermission()
        hasScreenRecordingPermission = granted
        return granted
    }
    
    private func checkCurrentScreenRecordingStatus() -> Bool {
        // Check if we have screen recording permission
        let options = CGWindowListOption.optionOnScreenOnly.union(.excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        return windowList != nil
    }
    
    private func requestScreenRecordingPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            // Request screen recording permission
            let granted = CGRequestScreenCaptureAccess()
            continuation.resume(returning: granted)
        }
    }
    
    private func startProfessionalAudioCapture(onStarted: @escaping (Bool) -> Void) async {
        // Professional approach: Use ScreenCaptureKit for system audio + screen
        do {
            try await startScreenCaptureWithAudio()
            setupAudioProcessing()
            
            // ✅ FIX: Set isRunning to true after successful capture start
            isRunning = true
            
            onStarted(true)
        } catch {
            print("❌ Failed to start professional audio capture: \(error.localizedDescription)")
            onStarted(false)
        }
    }
    
    private func setupAudioProcessing() {
        // Configure audio format conversion
        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)!
        targetFormat = sourceFormat
        
        // Set up audio engine for processing
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        converter = AVAudioConverter(from: inputFormat, to: sourceFormat)
        
        // Install tap for audio processing
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started for processing")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        
        // Convert buffer to target format
        guard let converter = converter,
              let targetFormat = targetFormat else { return }
        
        let frameCount = AVAudioFrameCount(buffer.frameLength)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("❌ Audio conversion error: \(error)")
            return 
        }
        
        // Process converted audio
        processConvertedAudio(outputBuffer)
    }
    
    private func processConvertedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData?[0] else { return }
        
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        
        // Convert Int16 samples to Data for Deepgram
        let sampleData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        accumulatingPCM.append(sampleData)
        accumulatedSamples += samples.count
        
        // Check if we have enough data for a chunk (50ms = 1600 bytes)
        while accumulatingPCM.count >= chunkSizeBytes {
            let chunk = accumulatingPCM.prefix(chunkSizeBytes)
            accumulatingPCM.removeFirst(chunkSizeBytes)
            
            // Send to Deepgram STT
            deepgramSTT.sendAudioData(Data(chunk))
        }
        
        // Voice activity detection
        let rms = calculateRMS(samples)
        if rms > voiceThreshold {
            lastVoiceActivity = Date()
            lastNonSilenceAt = Date()
        }
    }
    
    private func createAudioBuffer(from samples: [Int16]) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        guard let channelData = buffer.int16ChannelData?[0] else { return nil }
        
        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }
        
        return buffer
    }
    
    private func calculateRMS(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        // Convert to Double first to avoid Int16 overflow, then square
        // Use a more robust approach to prevent any potential overflow
        var sum: Double = 0.0
        for sample in samples {
            let sampleDouble = Double(sample)
            sum += sampleDouble * sampleDouble
        }
        
        let rms = sqrt(sum / Double(samples.count))
        return Float(rms)
    }
    
    func stopListening() {
        guard isRunning else { return }
        
        print("🛑 Stopping audio capture...")
        
        // Stop screen capture
        Task {
            try? await screenCaptureSession?.stopCapture()
            screenCaptureSession = nil
        }
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // ✅ FIX: Stop local speech transcriber
        SpeechTranscriber.shared.stop()
        
        // ✅ NEW: Stop WebSocket session if using it
        if useWebSocket {
            ListenAPI.shared.stopSession()
            // NEW: Don't disconnect immediately - let the WebSocket handle session completion
            // ListenAPI.shared.disconnect()
            
            // NEW: The onSessionFinished callback will handle transcript saving
            print("🔌 WebSocket session stopping, waiting for completion...")
        } else {
        // ✅ FIX: Call ListenAPI.stop to get server transcript before finishing session
        if let sid = sessionId {
            print("🔄 Requesting server transcript for session: \(sid)")
            
            // Add session summary transcript segment
            let sessionDuration = Date().timeIntervalSince(lastNonSilenceAt)
            let summaryText = "[Session Summary] Duration: \(String(format: "%.1f", sessionDuration))s - Audio capture completed"
            SessionTranscriptStore.shared.addTranscriptSegment(
                text: summaryText,
                confidence: 1.0,
                source: .final
            )
            
            // Call server to stop listening and get transcript
            ClientAPI.shared.listenStop(sessionId: sid) { [weak self] result in
                switch result {
                case .success(let response):
                    print("✅ Server transcript received")
                    print("🔍 DEBUG: Server response: \(response)")
                    // Server transcript is automatically added by ClientAPI.listenStop
                    
                case .failure(let error):
                    print("❌ Failed to get server transcript: \(error)")
                }
                
                // Always finish the session and save transcript file
                Task { @MainActor in
                        await self?.finishSession()
                    }
                }
            }
        }
        
        // Reset state
        isRunning = false
        accumulatingPCM.removeAll(keepingCapacity: true)
        accumulatedSamples = 0
        lastNonSilenceAt = Date()
        lastVoiceActivity = Date()
        debugBufferCount = 0
        
        print("✅ Audio capture stopped")
    }
    
    // MARK: - Force Cleanup (for app termination)
    
    func forceCleanup() {
        print("🔒 Force cleanup requested - stopping all audio capture")
        stopListening()
        
        // Additional force cleanup for app termination
        Task {
            // Force stop screen capture if still running
        if let session = screenCaptureSession {
                try? await session.stopCapture()
                screenCaptureSession = nil
            }
            
            // Force stop audio engine
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            
            // Force stop speech transcriber
            SpeechTranscriber.shared.stop()
            
            // Force disconnect WebSocket
            ListenAPI.shared.disconnect()
            
            print("✅ Force cleanup completed")
        }
    }
    
    // MARK: - Audio Processing (from screen capture)
    
    private func processAudioFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isListening else { return }
        
        // 🔍 DEBUG: Log every audio buffer received
        logger.debug("🎵 Audio buffer received - timestamp: \(Date())")
        lastAudioTimestamp = Date()
        isAudioFlowing = true
        
        // Discover source format from CMSampleBuffer
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            logger.error("❌ No audio format description")
            return
        }
        var asbd = asbdPtr.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd) else {
            logger.error("❌ Failed to create source AVAudioFormat")
            return
        }
        scInputFormat = sourceFormat
        
        // Build an AVAudioPCMBuffer and copy PCM from CMSampleBuffer safely
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            logger.error("❌ Failed to allocate source AVAudioPCMBuffer")
            return
        }
        srcBuffer.frameLength = frameCount
        // Use CoreMedia to copy PCM correctly (handles interleaved/planar and channel counts)
        let cmStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: srcBuffer.mutableAudioBufferList
        )
        if cmStatus != noErr {
            logger.error("❌ Failed to copy PCM into AVAudioPCMBuffer (status: \(cmStatus))")
            return
        }
        
        // Create or reuse converter to 16k mono Int16
        if scToDgConverter == nil || scToDgConverter?.inputFormat != sourceFormat {
            scToDgConverter = AVAudioConverter(from: sourceFormat, to: dgTargetFormat)
            logger.info("🔁 Created SC→DG converter: src sr=\(sourceFormat.sampleRate), ch=\(sourceFormat.channelCount), fmt=\(sourceFormat.commonFormat.rawValue) → 16k mono int16")
        }
        guard let converter = scToDgConverter,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: dgTargetFormat, frameCapacity: frameCount) else {
            logger.error("❌ Converter or output buffer unavailable")
            return
        }
        
        var convError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuffer
        }
        converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
        if let e = convError {
            logger.error("❌ Audio convert error: \(e.localizedDescription)")
            return
        }
        
        // Extract converted Int16 samples
        guard let ch = outBuffer.int16ChannelData else {
            logger.error("❌ No int16 channel data after conversion")
            return
        }
        let sampleCount = Int(outBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: ch[0], count: sampleCount))
        let sampleData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        accumulatingPCM.append(sampleData)
        accumulatedSamples += samples.count
        
        // Audio level for debug (converted domain)
        let audioLevel = calculateAudioLevel(samples: samples)
        DispatchQueue.main.async { self.audioLevelDebug = audioLevel }
        logger.debug("🔊 Audio level: \(audioLevel) dB, Samples: \(samples.count), Accum: \(self.accumulatingPCM.count) bytes")
        
        // Ensure 16-bit alignment
        assert(accumulatingPCM.count % 2 == 0, "PCM buffer misaligned (expected even number of bytes)")
        
        // Chunk and send (50ms = 1600 bytes @ 16k mono int16)
        while accumulatingPCM.count >= chunkSizeBytes {
            let chunk = accumulatingPCM.prefix(chunkSizeBytes)
            accumulatingPCM.removeFirst(chunkSizeBytes)
            let dataChunk = Data(chunk)
            deepgramSTT.sendAudioData(dataChunk)
            logger.debug("📦 Enqueued/sent audio chunk to Deepgram - size: \(chunk.count) bytes")
        }
        
        // Voice activity detection (converted samples)
        let rms = calculateRMS(samples)
        if rms > voiceThreshold {
            lastVoiceActivity = Date()
            lastNonSilenceAt = Date()
            logger.debug("🎤 Voice activity detected - RMS: \(rms)")
        }
    }
    
    // MARK: - Audio Chunk Management
    
    private func sendAudioChunk() {
        guard let sid = sessionId, accumulatedSamples > 0 else { return }
        
        let wav = self.wavData(fromPCM16: accumulatingPCM, sampleRate: Int(targetSampleRate), channels: 1)
        let chunkDuration = Double(accumulatedSamples) / targetSampleRate
        
        print("📤 Sending audio chunk: \(String(format: "%.1f", chunkDuration))s - \(wav.count) bytes")
        
        // ✅ FIX: Don't add audio chunk metadata to transcript - wait for actual Whisper response
        // The transcript will be populated by the WebSocket response from Whisper API
        
        // ✅ NEW: Use WebSocket if available, fallback to HTTP
        if useWebSocket {
            ListenAPI.shared.sendAudioChunk(audioData: wav)
        } else {
        ClientAPI.shared.listenSendChunk(sessionId: sid, audioData: wav, startSec: nil, endSec: nil) { ok in
            if ok {
                print("✅ Audio chunk sent successfully")
                    // Don't add server confirmation to transcript - it's not actual speech content
            } else {
                print("❌ Failed to send audio chunk")
                    // Only log errors, don't add to transcript
                }
            }
        }
        
        // Clear buffers after sending
        accumulatingPCM.removeAll(keepingCapacity: true)
        accumulatedSamples = 0
        lastNonSilenceAt = Date()
    }
    
    // MARK: - Audio Level Calculation
    
    private func calculateAudioLevel(samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return -100.0 }
        
        let sum = samples.reduce(0.0) { result, sample in
            return result + (Float(sample) * Float(sample))
        }
        
        let rms = sqrt(sum / Float(samples.count))
        let db = 20.0 * log10(rms / 32767.0)
        
        return db
    }
    
    // MARK: - Audio Quality Validation (Improved)
    
    private func validateAudioQuality(_ data: Data) -> AudioQuality {
        // Convert Data to Int16 samples
        let samples = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Int16.self))
        }
        
        // Safety check for empty data
        guard !samples.isEmpty else {
            return AudioQuality(
                silenceRatio: 0.0,
                dynamicRange: 0.0,
                clippingRate: 0.0,
                isAcceptable: false
            )
        }
        
        // Calculate audio quality metrics
        let silenceRatio = calculateSilenceRatio(samples)
        let dynamicRange = calculateDynamicRange(samples)
        let clippingRate = calculateClippingRate(samples)
        
        // Determine if quality is acceptable
        let isAcceptable = silenceRatio < 0.8 && dynamicRange > 20.0 && clippingRate < 0.1
        
        return AudioQuality(
            silenceRatio: silenceRatio,
            dynamicRange: dynamicRange,
            clippingRate: clippingRate,
            isAcceptable: isAcceptable
        )
    }
    
    private func calculateSilenceRatio(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let silenceThreshold: Int16 = 100
        let silentSamples = samples.filter { abs($0) < silenceThreshold }.count
        return Float(silentSamples) / Float(samples.count)
    }
    
    private func calculateDynamicRange(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let maxSample = Float(samples.map { abs($0) }.max() ?? 0)
        let minSample = Float(samples.map { abs($0) }.filter { $0 > 0 }.min() ?? 1)
        
        if minSample <= 0 { return 0.0 }
        
        return 20 * log10(maxSample / minSample)
    }
    
    private func calculateClippingRate(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let clippingThreshold: Int16 = 32000
        let clippedSamples = samples.filter { abs($0) >= clippingThreshold }.count
        return Float(clippedSamples) / Float(samples.count)
    }
    
    // MARK: - WAV Conversion
    
    private func wavData(fromPCM16 pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = pcmData.count
        let fileSize = 44 + dataSize
        
        var wavData = Data()
        
        // WAV header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Data($0) })
        wavData.append(contentsOf: "WAVE".utf8)
        
        // Format chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate * channels * bytesPerSample).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(channels * bytesPerSample).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(bytesPerSample * 8).littleEndian) { Data($0) })
        
        // Data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        wavData.append(pcmData)
        
        return wavData
    }
}

// MARK: - SCStreamDelegate

extension AudioCaptureManager: @preconcurrency SCStreamDelegate, @preconcurrency SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            processAudioFromSampleBuffer(sampleBuffer)
        case .screen:
            // Handle screen updates if needed
            break
        case .microphone:
            // Handle microphone input if needed
            break
        @unknown default:
            print("⚠️ Unknown sample buffer type: \(type)")
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ Screen capture stream stopped with error: \(error)")
        isRunning = false
    }
}

// MARK: - Audio Capture Errors

enum AudioCaptureError: Error, LocalizedError {
    case noDisplayAvailable
    case permissionDenied
    case audioEngineFailed
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available for capture"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .audioEngineFailed:
            return "Audio engine failed to start"
        }
    }
}


