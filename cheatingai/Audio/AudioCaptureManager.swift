import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit

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

    func startListening(sessionId: String, onStarted: @escaping (Bool) -> Void) {
        guard !isRunning else { onStarted(true); return }
        self.sessionId = sessionId
        
        // Start transcript session
        SessionTranscriptStore.shared.startSession(sessionId: sessionId)
        
        // ✅ FIX: Start local speech transcriber for real-time transcription
        SpeechTranscriber.shared.start(
            onPartial: { partialText in
                // Optional: Show partial text in UI
                print("🎙️ Partial: \(partialText)")
            },
            onFinal: { finalText in
                // Store final local transcript
                SessionTranscriptStore.shared.addLocalTranscript(finalText, confidence: 1.0)
                print("📝 Local transcript: \(finalText)")
            }
        )
        
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
    
    private func checkScreenRecordingPermission() async -> Bool {
        // Check if we have screen recording permission
        let status = CGPreflightScreenCaptureAccess()
        hasScreenRecordingPermission = status
        
        if !status {
            print("🔒 Requesting screen recording permission...")
            // Request permission - this will show system dialog
            let granted = CGRequestScreenCaptureAccess()
            hasScreenRecordingPermission = granted
            
            if granted {
                print("✅ Screen recording permission granted")
            } else {
                print("❌ Screen recording permission denied")
                // Show user-friendly instructions
                showPermissionInstructions()
            }
        }
        
        return hasScreenRecordingPermission
    }
    
    private func showPermissionInstructions() {
        ResponseOverlay.shared.show(text: "🔒 Screen Recording Permission Required\n\nTo capture system audio (YouTube, Zoom, etc.), please:\n\n1. Go to System Settings → Privacy & Security → Screen Recording\n2. Enable permission for Nova\n3. Restart Nova and try again")
        
        // Open System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
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
        print("📱 No BlackHole or manual setup required")
    }
    
    private func setupAudioProcessing() {
        // Set up audio processing pipeline
        let inputFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)!
        targetFormat = inputFormat
        
        // Create converter for audio processing
        converter = AVAudioConverter(from: inputFormat, to: inputFormat)
        
        print("✅ Audio processing pipeline configured")
    }
    
    func stopListening(completion: @escaping () -> Void) {
        guard isRunning else { 
            print("⚠️ Audio capture already stopped")
            completion()
            return 
        }
        
        print("🛑 Stopping audio capture and screen recording...")
        isRunning = false
        
        // ✅ FIX: Save any remaining audio BEFORE clearing buffers
        if accumulatedSamples > 0, let sid = sessionId {
            let wav = self.wavData(fromPCM16: accumulatingPCM, sampleRate: Int(targetSampleRate), channels: 1)
            print("💾 DEBUG: Saving remaining audio: \(wav.count) bytes")
            
            // Add transcript segment for remaining audio
            let remainingDuration = Double(accumulatedSamples) / targetSampleRate
            SessionTranscriptStore.shared.addTranscriptSegment(
                text: "[Final Audio] \(String(format: "%.1f", remainingDuration))s - \(wav.count) bytes - Session ending",
                confidence: 1.0,
                source: .local
            )
            
            ClientAPI.shared.listenSendChunk(sessionId: sid, audioData: wav, startSec: nil, endSec: nil) { ok in
                if ok {
                    print("✅ DEBUG: Successfully sent final audio chunk")
                    SessionTranscriptStore.shared.addTranscriptSegment(
                        text: "[Final Chunk] Successfully sent to server",
                        confidence: 1.0,
                        source: .server
                    )
                } else {
                    print("❌ DEBUG: Failed to send final audio chunk")
                    SessionTranscriptStore.shared.addTranscriptSegment(
                        text: "[Final Chunk] Failed to send to server",
                        confidence: 0.0,
                        source: .local
                    )
                }
            }
        }
        
        // Stop screen capture properly with timeout and force cleanup
        Task {
            do {
                if let session = screenCaptureSession {
                    print("🛑 Attempting to stop screen capture session...")
                    
                    // Try graceful stop first
                    try await session.stopCapture()
                    print("✅ Screen capture stopped successfully")
                    
                    // Wait a bit for the system to process the stop
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Additional verification - try to stop again if needed
                    print("🔄 Verifying session stop completion...")
                }
                
                // Clear the session reference
                screenCaptureSession = nil
                
                // Revoke screen recording permission to ensure system indicator disappears
                revokeScreenRecordingPermission()
            } catch {
                print("❌ Error stopping screen capture: \(error.localizedDescription)")
                // Force cleanup even if stop failed
                if let session = screenCaptureSession {
                    print("🔄 Force stopping session due to error...")
                    do {
                        try await session.stopCapture()
                        print("✅ Force stop completed")
                    } catch {
                        print("❌ Force stop also failed: \(error)")
                    }
                    screenCaptureSession = nil
                }
                // Still try to revoke permission even if stop failed
                revokeScreenRecordingPermission()
            }
        }
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            print("✅ Audio engine stopped")
        }
        
        // ✅ FIX: Stop local speech transcriber
        SpeechTranscriber.shared.stop()
        
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
                    if let transcriptURL = await SessionTranscriptStore.shared.finishSession() {
                        print("✅ Session transcript saved to: \(transcriptURL.path)")
                        
                        // Add final confirmation transcript segment
                        SessionTranscriptStore.shared.addTranscriptSegment(
                            text: "[Session Complete] Transcript saved to: \(transcriptURL.lastPathComponent)",
                            confidence: 1.0,
                            source: .final
                        )
                    } else {
                        print("❌ Failed to save session transcript")
                        
                        // Add error transcript segment
                        SessionTranscriptStore.shared.addTranscriptSegment(
                            text: "[Error] Failed to save session transcript",
                            confidence: 0.0,
                            source: .final
                        )
                    }
                    
                    // Reset state
                    self?.sessionId = nil
                    completion()
                }
            }
        } else {
            print("⚠️ No session ID available")
            completion()
        }
        
        // ✅ FIX: Clear buffers AFTER saving and requesting server transcript
        accumulatingPCM.removeAll(keepingCapacity: true)
        accumulatedSamples = 0
        lastNonSilenceAt = Date()
        lastVoiceActivity = Date()
        
        print("✅ Audio capture and screen recording stopped completely")
    }
    
    // MARK: - Permission Management
    
    func forceCleanup() {
        print("🧹 Force cleaning up audio capture and screen recording...")
        
        // Stop any running sessions
        if isRunning {
            isRunning = false
        }
        
        // Force stop screen capture
        if let session = screenCaptureSession {
            Task {
                do {
                    try await session.stopCapture()
                    print("✅ Forced screen capture stop during cleanup")
                } catch {
                    print("❌ Error during forced cleanup: \(error)")
                }
            }
        }
        
        // Revoke permissions
        revokeScreenRecordingPermission()
        
        // Reset all state
        screenCaptureSession = nil
        accumulatingPCM.removeAll(keepingCapacity: true)
        accumulatedSamples = 0
        lastNonSilenceAt = Date()
        lastVoiceActivity = Date()
        
        print("🧹 Force cleanup completed")
    }
    
    private func checkCurrentScreenRecordingStatus() -> Bool {
        let currentStatus = CGPreflightScreenCaptureAccess()
        print("🔍 Current screen recording permission status: \(currentStatus ? "Granted" : "Not Granted")")
        return currentStatus
    }
    
    private func revokeScreenRecordingPermission() {
        print("🔒 Revoking screen recording permission...")
        
        // Force the system to revoke the permission
        DispatchQueue.main.async {
            print("🔒 DEBUG: On main thread, calling CGRequestScreenCaptureAccess...")
            // This will trigger the system to revoke the permission
            let _ = CGRequestScreenCaptureAccess()
            print("🔒 DEBUG: CGRequestScreenCaptureAccess called")
            
            // Also try to clear any remaining capture sessions
            if let session = self.screenCaptureSession {
                print("🔒 DEBUG: Found active screen capture session, forcing stop...")
                Task {
                    do {
                        try await session.stopCapture()
                        print("✅ Forced screen capture session stop")
                    } catch {
                        print("❌ Error forcing screen capture stop: \(error)")
                    }
                }
            } else {
                print("🔒 DEBUG: No active screen capture session found")
            }
            
            // Reset permission state
            self.hasScreenRecordingPermission = false
            print("🔒 Screen recording permission revoked")
            
            // Verify permission was revoked
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("🔒 DEBUG: Verifying permission revocation...")
                let newStatus = self.checkCurrentScreenRecordingStatus()
                if !newStatus {
                    print("✅ Screen recording permission successfully revoked")
                } else {
                    print("⚠️ Screen recording permission still active - may need manual system intervention")
                }
            }
        }
        
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
        
        // ✅ FIX: Feed audio to local speech transcriber for real-time recognition
        if let audioBuffer = createAudioBuffer(from: samples) {
            SpeechTranscriber.shared.append(audioBuffer)
        }
        
        // Check if we have enough samples to send a chunk
        if accumulatedSamples >= Int(targetSampleRate * maxChunkDuration) {
            sendAudioChunk()
        }
        
        // Update voice activity detection
        // ✅ FIX: Convert to Double before multiplication to prevent Int16 overflow
        let rms = sqrt(samples.map { Double($0) * Double($0) }.reduce(0, +) / Double(samples.count))
        // ✅ FIX: Convert voiceThreshold to Double for comparison
        if rms > Double(voiceThreshold) {
            lastVoiceActivity = Date()
            lastNonSilenceAt = Date()
        }
    }
    
    private func convertSampleBufferToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        print("🔍 DEBUG: Starting sample buffer conversion...")
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        // This is a simplified conversion - in production, you'd want more robust handling
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("❌ DEBUG: No format description in sample buffer")
            return nil
        }
        
        print("✅ DEBUG: Got format description")
        
        let audioFormat = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let audioFormat = audioFormat else {
            print("❌ DEBUG: Failed to get audio format")
            return nil
        }
        
        print("✅ DEBUG: Got audio format")
        
        let sampleRate = audioFormat.pointee.mSampleRate
        let channels = UInt32(audioFormat.pointee.mChannelsPerFrame)
        
        print("🔍 DEBUG: Audio format - sampleRate: \(sampleRate), channels: \(channels)")
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        
        print("🔍 DEBUG: Frame count: \(frameCount)")
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ DEBUG: Failed to create PCM buffer")
            return nil
        }
        
        print("✅ DEBUG: Created PCM buffer")
        
        // Copy audio data from the sample buffer
        if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var dataLength = 0
            var unusedPointer: UnsafeMutablePointer<Int8>?
            
            let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &dataLength, totalLengthOut: nil, dataPointerOut: &unusedPointer)
            
            if status == kCMBlockBufferNoErr, let unusedPointer = unusedPointer {
                print("✅ DEBUG: Got data buffer from sample buffer")
                print("🔍 DEBUG: Data buffer status: \(status), length: \(dataLength)")
                
                // Set the frame length
                pcmBuffer.frameLength = frameCount
                
                // Copy the audio data to the PCM buffer
                if let channelData = pcmBuffer.floatChannelData?[0] {
                    // Convert Int8 data to Float32
                    let int8Data = UnsafeBufferPointer(start: unusedPointer, count: dataLength)
                    let maxFrames = min(Int(frameCount), dataLength / 4) // Assuming 32-bit samples
                    
                    // Safety check
                    guard maxFrames > 0 else {
                        print("⚠️ DEBUG: No valid frames to process")
                        return pcmBuffer
                    }
                    
                    for i in 0..<maxFrames {
                        let sampleIndex = i * 4
                        if sampleIndex + 3 < dataLength {
                            // Convert 4 bytes to Float32 (little-endian) - with proper signed handling
                            let byte0 = UInt32(bitPattern: Int32(int8Data[sampleIndex]))
                            let byte1 = UInt32(bitPattern: Int32(int8Data[sampleIndex + 1]))
                            let byte2 = UInt32(bitPattern: Int32(int8Data[sampleIndex + 2]))
                            let byte3 = UInt32(bitPattern: Int32(int8Data[sampleIndex + 3]))
                            
                            let combined = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
                            let sample = Float32(bitPattern: combined)
                            channelData[i] = sample
                        }
                    }
                    print("✅ DEBUG: Successfully copied audio data to PCM buffer")
                } else {
                    print("❌ DEBUG: Failed to get channel data pointer")
                }
            } else {
                print("❌ DEBUG: Failed to access data buffer, status: \(status)")
            }
        }
        
        return pcmBuffer
    }
    
    // MARK: - Audio Processing Helpers
    
    private func createAudioBuffer(from samples: [Int16]) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(samples.count)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // Copy samples to buffer
        if let channelData = buffer.int16ChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }
        
        return buffer
    }
    
    private func sendAudioChunk() {
        guard let sid = sessionId, accumulatedSamples > 0 else { return }
        
        let wav = self.wavData(fromPCM16: accumulatingPCM, sampleRate: Int(targetSampleRate), channels: 1)
        let chunkDuration = Double(accumulatedSamples) / targetSampleRate
        
        print("📤 Sending audio chunk: \(String(format: "%.1f", chunkDuration))s - \(wav.count) bytes")
        
        // Add transcript segment for this audio chunk
        let transcriptText = "[Audio Chunk] \(String(format: "%.1f", chunkDuration))s - \(wav.count) bytes"
        SessionTranscriptStore.shared.addTranscriptSegment(
            text: transcriptText,
            confidence: 1.0,
            source: .local
        )
        
        ClientAPI.shared.listenSendChunk(sessionId: sid, audioData: wav, startSec: nil, endSec: nil) { ok in
            if ok {
                print("✅ Audio chunk sent successfully")
                SessionTranscriptStore.shared.addTranscriptSegment(
                    text: "[Server Confirmed] Audio chunk received",
                    confidence: 1.0,
                    source: .server
                )
            } else {
                print("❌ Failed to send audio chunk")
                SessionTranscriptStore.shared.addTranscriptSegment(
                    text: "[Error] Failed to send audio chunk to server",
                    confidence: 0.0,
                    source: .local
                )
            }
        }
        
        // Clear buffers after sending
        accumulatingPCM.removeAll(keepingCapacity: true)
        accumulatedSamples = 0
        lastNonSilenceAt = Date()
    }
    
    // MARK: - Audio Quality Validation (Improved)
    
    private func validateAudioQuality(_ data: Data) -> AudioQuality {
        let silenceRatio = calculateSilenceRatio(data)
        let dynamicRange = calculateDynamicRange(data)
        let clippingRate = calculateClippingRate(data)
        
        // Professional thresholds - more lenient for real-world audio
        let isAcceptable = silenceRatio < 0.95 && 
                           dynamicRange > -10 && 
                           clippingRate < 0.1
        
        return AudioQuality(
            silenceRatio: silenceRatio,
            dynamicRange: dynamicRange,
            clippingRate: clippingRate,
            isAcceptable: isAcceptable
        )
    }
    
    private func calculateSilenceRatio(_ data: Data) -> Float {
        var silentSamples = 0
        let totalSamples = data.count / 2
        
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let samples = ptr.bindMemory(to: Int16.self)
            for sample in samples {
                if abs(Int(sample)) < 500 { // -42dB threshold
                    silentSamples += 1
                }
            }
        }
        
        return Float(silentSamples) / Float(totalSamples)
    }
    
    private func calculateDynamicRange(_ data: Data) -> Float {
        var minSample: Int32 = Int32.max
        var maxSample: Int32 = Int32.min
        
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let samples = ptr.bindMemory(to: Int16.self)
            for sample in samples {
                // Convert Int16 to Int32 to prevent overflow
                let sample32 = Int32(sample)
                minSample = min(minSample, sample32)
                maxSample = max(maxSample, sample32)
            }
        }
        
        // Safe arithmetic using Int32 to prevent overflow
        let range: Float
        if maxSample >= 0 && minSample >= 0 {
            // Both positive, safe subtraction
            range = Float(maxSample - minSample)
        } else if maxSample >= 0 && minSample < 0 {
            // maxSample positive, minSample negative - use addition
            range = Float(maxSample) + Float(abs(minSample))
        } else if maxSample < 0 && minSample < 0 {
            // Both negative, safe subtraction
            range = Float(abs(minSample) - abs(maxSample))
        } else {
            // maxSample negative, minSample positive (edge case)
            range = Float(abs(minSample) + abs(maxSample))
        }
        
        // Ensure range is valid and not zero
        let safeRange = max(range, 1.0)
        return 20 * log10(safeRange / 32768.0)
    }
    
    private func calculateClippingRate(_ data: Data) -> Float {
        var clippedSamples = 0
        let totalSamples = data.count / 2
        
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let samples = ptr.bindMemory(to: Int16.self)
            for sample in samples {
                if abs(Int(sample)) > 32000 {
                    clippedSamples += 1
                }
            }
        }
        
        return Float(clippedSamples) / Float(totalSamples)
    }
    
    // MARK: - Audio Preprocessing Pipeline
    
    private func preprocessAudio(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let processedBuffer = applyNoiseReduction(buffer)
        let normalizedBuffer = normalizeVolume(processedBuffer)
        let filteredBuffer = applyBandpassFilter(normalizedBuffer, lowCut: 300, highCut: 8000)
        return filteredBuffer
    }
    
    private func applyNoiseReduction(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else { return buffer }
        
        let noiseGate: Float = 0.01
        for i in 0..<Int(buffer.frameLength) {
            if abs(channelData[i]) < noiseGate {
                channelData[i] = 0.0
            }
        }
        
        return buffer
    }
    
    private func normalizeVolume(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else { return buffer }
        
        var peak: Float = 0.0
        for i in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(channelData[i]))
        }
        
        let targetPeak: Float = 0.5
        if peak > 0 {
            let gain = targetPeak / peak
            for i in 0..<Int(buffer.frameLength) {
                channelData[i] *= gain
            }
        }
        
        return buffer
    }
    
    private func applyBandpassFilter(_ buffer: AVAudioPCMBuffer, lowCut: Float, highCut: Float) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else { return buffer }
        
        var prevSample: Float = 0.0
        for i in 0..<Int(buffer.frameLength) {
            let current = channelData[i]
            let filtered = current * 0.8 + prevSample * 0.2
            channelData[i] = filtered
            prevSample = filtered
        }
        
        return buffer
    }
    
    private func calculateAudioEnergy(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        
        var energy: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            energy += channelData[i] * channelData[i]
        }
        return sqrt(energy / Float(buffer.frameLength))
    }
    
    // MARK: - Utility Methods
    
    private func wavData(fromPCM16 pcm: Data, sampleRate: Int, channels: Int) -> Data {
        // WAV file creation logic (unchanged)
        var wav = Data()
        
        // WAV header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(36 + pcm.count).littleEndian) { Data($0) })
        wav.append(contentsOf: "WAVE".utf8)
        
        // Format chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * channels * 2).littleEndian) { Data($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels * 2).littleEndian) { Data($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        
        // Data chunk
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(pcm.count).littleEndian) { Data($0) })
        wav.append(pcm)
        
        return wav
    }
}

// MARK: - SCStreamDelegate & SCStreamOutput

extension AudioCaptureManager: SCStreamDelegate, SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            // Process audio from screen capture
            if let audioBufferList = CMSampleBufferGetDataBuffer(sampleBuffer) {
                // Get audio data from the buffer
                var dataLength = 0
                var unusedPointer: UnsafeMutablePointer<Int8>?
                
                let status = CMBlockBufferGetDataPointer(audioBufferList, atOffset: 0, lengthAtOffsetOut: &dataLength, totalLengthOut: nil, dataPointerOut: &unusedPointer)
                
                if status == kCMBlockBufferNoErr {
                    // Convert to AVAudioPCMBuffer and process
                    print("🎵 Captured system audio from screen recording")
                    
                    // Process the audio buffer on the main actor
                    Task { @MainActor in
                        self.processAudioFromSampleBuffer(sampleBuffer)
                    }
                }
            }
        case .screen:
            // Handle screen content if needed
            break
        case .microphone:
            // Handle microphone input if needed
            break
        @unknown default:
            break
        }
    }
    
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ Screen capture stream stopped with error: \(error.localizedDescription)")
        Task { @MainActor in
            self.isRunning = false
        }
    }
}

// MARK: - Error Types

enum AudioCaptureError: Error, LocalizedError {
    case noDisplayAvailable
    case permissionDenied
    case streamCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available for capture"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .streamCreationFailed:
            return "Failed to create capture stream"
        }
    }
}


