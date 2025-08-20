import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

// MARK: - Audio Quality Models

struct AudioQuality {
    let silenceRatio: Float      // 0.0 = no silence, 1.0 = all silence
    let dynamicRange: Float      // Dynamic range in dB
    let clippingRate: Float      // 0.0 = no clipping, 1.0 = all clipped
    let isAcceptable: Bool       // Overall quality assessment
}

@MainActor
final class AudioCaptureManager: NSObject {
    static let shared = AudioCaptureManager()

    // MARK: - Professional Audio Capture Properties
    private var screenCaptureSession: SCStream?
    private var audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    
    // Audio processing
    private var accumulatingPCM = Data()
    private var accumulatedSamples: Int = 0
    private let targetSampleRate: Double = 16_000
    private let chunkSeconds: Double = 3
    private var samplesPerChunk: Int { Int(targetSampleRate * chunkSeconds) }
    
    // Session management
    private var sessionId: String?
    private var isRunning = false
    private var debugBufferCount: Int = 0
    private var lastNonSilenceAt: Date = Date()
    private var lastVoiceActivity: Date = Date()
    
    // VAD Configuration
    private let voiceThreshold: Float = 0.01
    private let maxChunkDuration: Double = 10.0
    
    // Screen recording permission
    private var hasScreenRecordingPermission = false
    
    // WebSocket integration
    private var useWebSocket = true
    private var webSocketTranscript = ""

    func startListening(sessionId: String, onStarted: @escaping (Bool) -> Void) {
        guard !isRunning else { onStarted(true); return }
        self.sessionId = sessionId
        
        // Start transcript session
        SessionTranscriptStore.shared.startSession(sessionId: sessionId)
        
        // ✅ NEW: Initialize WebSocket connection for real-time transcription
        if useWebSocket {
            setupWebSocket()
        }
        
        // ✅ FIX: Only use local speech transcriber as fallback if WebSocket fails
        if !useWebSocket {
        SpeechTranscriber.shared.start(
            onPartial: { partialText in
                // Optional: Show partial text in UI
                print("🎙️ Partial: \(partialText)")
            },
            onFinal: { finalText in
                    // Store final local transcript (only when WebSocket is not available)
                SessionTranscriptStore.shared.addLocalTranscript(finalText, confidence: 1.0)
                    print("📝 Local transcript (fallback): \(finalText)")
            }
        )
        }
        
        // Check and request screen recording permission
        Task {
            let hasPermission = await checkScreenRecordingPermission()
            if !hasPermission {
                print("❌ Screen recording permission required for system audio capture")
                onStarted(false)
                return
            }
            
            // Start professional audio capture
            await startProfessionalAudioCapture(onStarted: onStarted)
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
    
    private func startScreenCaptureWithAudio() async throws {
        // Get available content for screen + audio capture
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = availableContent.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }
        
        // Configure stream for screen + audio capture
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.capturesAudio = true  // This captures system audio!
        configuration.sampleRate = Int(targetSampleRate)
        configuration.channelCount = 1
        
        // Create and start the capture stream
        screenCaptureSession = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        // Add audio stream output
        try screenCaptureSession?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        
        // Start capture
        try await screenCaptureSession?.startCapture()
        
        print("✅ Professional audio capture started - capturing system audio + screen")
        print("🎧 System audio capture enabled via Screen Recording permission")
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
        
        // ✅ FIX: Convert Int16 samples to Data before appending
        let sampleData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        accumulatingPCM.append(sampleData)
        accumulatedSamples += samples.count
        
        // ✅ FIX: Only feed audio to local speech transcriber if WebSocket is not available
        if !useWebSocket, let audioBuffer = createAudioBuffer(from: samples) {
            SpeechTranscriber.shared.append(audioBuffer)
        }
        
        // Check if we have enough samples for a chunk
        if accumulatedSamples >= samplesPerChunk {
            sendAudioChunk()
        }
        
        // Voice activity detection
        let rms = calculateRMS(samples)
        if rms > voiceThreshold {
            lastVoiceActivity = Date()
            lastNonSilenceAt = Date()
        }
        
        // Auto-stop if too much silence
        let silenceDuration = Date().timeIntervalSince(lastVoiceActivity)
        if silenceDuration > maxChunkDuration && accumulatedSamples > 0 {
            sendAudioChunk()
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
    
    private func finishSession() async {
        // Save final transcript
        let _ = await SessionTranscriptStore.shared.finishSession()
        
        // Clean up any remaining resources
        print("✅ Session finished and transcript saved")
        
        // Additional cleanup: try to force stop any lingering processes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("🔒 DEBUG: Additional cleanup - checking for lingering sessions...")
            
            // Try to force revoke again
            let _ = CGRequestScreenCaptureAccess()
            
            // Check if we need to manually clear the permission
            if self.checkCurrentScreenRecordingStatus() {
                print("⚠️ Permission still active after 2 seconds, attempting manual cleanup...")
                // Try to trigger system permission dialog to force user to revoke
                let _ = CGRequestScreenCaptureAccess()
            }
        }
    }
    
    // MARK: - Audio Processing (from screen capture)
    
    private func processAudioFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        
        // Extract audio data from sample buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return }
        
        // Convert to PCM16 samples
        let samples = dataPointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { pointer in
            Array(UnsafeBufferPointer(start: pointer, count: length / 2))
        }
        
        // ✅ FIX: Convert Int16 samples to Data before appending
        let sampleData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        accumulatingPCM.append(sampleData)
        accumulatedSamples += samples.count
        
        // ✅ FIX: Only feed audio to local speech transcriber if WebSocket is not available
        if !useWebSocket, let audioBuffer = createAudioBuffer(from: samples) {
            SpeechTranscriber.shared.append(audioBuffer)
        }
        
        // Check if we have enough samples for a chunk
        if accumulatedSamples >= samplesPerChunk {
            sendAudioChunk()
        }
        
        // Voice activity detection
        let rms = calculateRMS(samples)
        if rms > voiceThreshold {
            lastVoiceActivity = Date()
            lastNonSilenceAt = Date()
        }
        
        // Auto-stop if too much silence
        let silenceDuration = Date().timeIntervalSince(lastVoiceActivity)
        if silenceDuration > maxChunkDuration && accumulatedSamples > 0 {
            sendAudioChunk()
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


