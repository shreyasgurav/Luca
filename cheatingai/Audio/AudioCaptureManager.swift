import Foundation
import AVFoundation
import AppKit

@MainActor
final class AudioCaptureManager: NSObject {
    static let shared = AudioCaptureManager()

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private var accumulatingPCM = Data()
    private var accumulatedSamples: Int = 0
    private let targetSampleRate: Double = 16_000
    private let chunkSeconds: Double = 3
    private var samplesPerChunk: Int { Int(targetSampleRate * chunkSeconds) }

    private var sessionId: String?
    private var isRunning = false
    private var debugBufferCount: Int = 0
    private var lastNonSilenceAt: Date = Date()
    private var silenceTimer: Timer?
    private var didWarnNoAudio: Bool = false
    private var didLaunchGuides: Bool = false

    func startListening(sessionId: String, onStarted: @escaping (Bool) -> Void) {
        guard !isRunning else { onStarted(true); return }
        self.sessionId = sessionId
        
        // Start transcript session
        SessionTranscriptStore.shared.startSession(sessionId: sessionId)
        
        // Validate audio setup before proceeding
        guard validateAudioSetup() else {
            print("❌ Audio setup validation failed")
            onStarted(false)
            return
        }
        
        setupAudioSession()
        handleAudioDeviceChange()

        // Get the input and output nodes
        let input = engine.inputNode
        let output = engine.outputNode
        
        // Nodes are always available on macOS
        
        // Connect input to output to ensure the audio graph is valid
        engine.connect(input, to: output, format: input.inputFormat(forBus: 0))
        
        // Verify the connection was successful
        print("🔗 Audio graph: Input → Output connected")
        
        // Now prepare the engine AFTER configuring the audio graph
        engine.prepare()
        print("✅ Audio engine prepared successfully")
        
        let inputFormat = input.inputFormat(forBus: 0)
        
        // Validate input format
        guard inputFormat.channelCount > 0 && inputFormat.sampleRate > 0 else {
            print("❌ Invalid input format: channels=\(inputFormat.channelCount), sampleRate=\(inputFormat.sampleRate)")
            onStarted(false)
            return
        }

        // Target: PCM 16-bit, mono, 16kHz (non-interleaved so int16ChannelData is available)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            print("❌ Failed to create target audio format")
            onStarted(false)
            return
        }
        
        targetFormat = target
        
        // Create converter with error handling
        guard let audioConverter = AVAudioConverter(from: inputFormat, to: target) else {
            print("❌ Failed to create audio converter from \(inputFormat) to \(target)")
            onStarted(false)
            return
        }
        converter = audioConverter

        // Remove any existing tap and install new one
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Feed Apple Speech with original input stream for local transcription
            // Ensure mono 16k for recognizer if needed; otherwise pass original
            SpeechTranscriber.shared.append(buffer)
            self.handleIncoming(buffer: buffer)
        }

        do {
            // Engine is already prepared from setupAudioSession
            
            // Verify the engine is properly configured
            guard engine.isRunning == false else {
                print("❌ Engine is already running")
                onStarted(false)
                return
            }
            
            // Engine nodes should always be available on macOS
            
            try engine.start()
            isRunning = true
            print("🎧 AudioCaptureManager: engine started, sampleRate=\(inputFormat.sampleRate), ch=\(inputFormat.channelCount)")
            lastNonSilenceAt = Date()
            didWarnNoAudio = false
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.isRunning { return }
                    if Date().timeIntervalSince(self.lastNonSilenceAt) > 5.0 && !self.didWarnNoAudio {
                        self.didWarnNoAudio = true
                        ResponseOverlay.shared.show(text: "🔇 No audio detected. To capture system audio, route output to a virtual device. Steps: 1) Install BlackHole, 2) Set Output: Multi-Output (Speakers + BlackHole), 3) Set Input: BlackHole 2ch, then Listen again.")
                        // Open Sound settings
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                            NSWorkspace.shared.open(url)
                        }
                        // Open Audio MIDI Setup to create Multi-Output device
                        let midiApp = URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")
                        NSWorkspace.shared.open(midiApp)
                        // Open BlackHole install page (one-time)
                        if !self.didLaunchGuides, let gh = URL(string: "https://github.com/ExistentialAudio/BlackHole") {
                            self.didLaunchGuides = true
                            NSWorkspace.shared.open(gh)
                        }
                    }
                }
            }
            onStarted(true)
        } catch {
            print("❌ AudioCaptureManager: engine.start failed: \(error.localizedDescription)")
            
            // Clean up on failure
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            
            // Try to reset the engine and retry once
            if error.localizedDescription.contains("inputNode != nullptr") || 
               error.localizedDescription.contains("outputNode != nullptr") ||
               error.localizedDescription.contains("required condition is false") {
                print("🔄 Attempting to reset audio engine and retry...")
                resetAudioEngine()
                
                // Wait a moment and try again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    print("🔄 Retrying audio start after reset...")
                    self.startListening(sessionId: sessionId, onStarted: onStarted)
                }
                return
            }
            
            onStarted(false)
        }
    }

    func stopListening(completion: @escaping () -> Void) {
        guard isRunning else { completion(); return }
        
        // Clean up audio engine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        // Reset state
        isRunning = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        didWarnNoAudio = false
        didLaunchGuides = false
        
        // Clean up accumulated data
        accumulatingPCM.removeAll(keepingCapacity: true)
        accumulatedSamples = 0
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Flush remaining chunk if any
        if accumulatedSamples > 0, let sid = sessionId {
            let wav = self.wavData(fromPCM16: accumulatingPCM, sampleRate: Int(targetSampleRate), channels: 1)
            ClientAPI.shared.listenSendChunk(sessionId: sid, audioData: wav, startSec: nil, endSec: nil) { _ in }
        }

        // Save transcript and finish session
        Task { @MainActor in
            if let transcriptURL = await SessionTranscriptStore.shared.finishSession() {
                print("✅ Session transcript saved to: \(transcriptURL.path)")
            }
            completion()
        }
    }

    private func setupAudioSession() {
        #if os(macOS)
        // macOS: AVAudioEngine needs explicit input/output node configuration
        // Get available input devices using modern API
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discoverySession.devices
        guard !devices.isEmpty else {
            print("❌ No audio input devices found")
            return
        }
        
        // Set preferred input device if available
        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            print("✅ Using default audio input: \(defaultDevice.localizedName)")
        }
        
        // On macOS, AVAudioEngine should have input/output nodes by default
        // We'll prepare the engine after configuring the audio graph
        print("✅ Audio session setup complete")
        #else
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        #endif
    }

    private func handleIncoming(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }

        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(buffer.frameLength)) else { 
            print("⚠️ Failed to create converted audio buffer")
            return 
        }
        
        var error: NSError?
        let status = converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        
        if status != .haveData {
            if let error = error {
                print("⚠️ Audio conversion failed: \(error.localizedDescription)")
            } else {
                print("⚠️ Audio conversion failed with status: \(status)")
            }
            return
        }

        let frames = Int(converted.frameLength)
        let byteCount = frames * MemoryLayout<Int16>.size
        var data = Data()
        if let ch0 = converted.int16ChannelData?[0] {
            data = Data(bytes: ch0, count: byteCount)
        } else if let mData = converted.audioBufferList.pointee.mBuffers.mData {
            data = Data(bytes: mData, count: byteCount)
        } else {
            return
        }

        accumulatingPCM.append(data)
        accumulatedSamples += frames

        var peak: Int = 0
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let p = ptr.bindMemory(to: Int16.self)
            for s in p {
                let v = Int(s.magnitude)
                if v > peak { peak = v }
            }
        }
        if peak > 500 { lastNonSilenceAt = Date(); didWarnNoAudio = false }

        // Light debug logging to confirm audio flow
        debugBufferCount += 1
        if debugBufferCount % 30 == 0 {
            print("🎙️ AudioCaptureManager: converted frames=\(frames), accumulatedSamples=\(accumulatedSamples)")
        }

        if accumulatedSamples >= samplesPerChunk, let sid = sessionId {
            let wav = self.wavData(fromPCM16: accumulatingPCM, sampleRate: Int(targetSampleRate), channels: 1)
            accumulatingPCM.removeAll(keepingCapacity: true)
            accumulatedSamples = 0

            ClientAPI.shared.listenSendChunk(sessionId: sid, audioData: wav, startSec: nil, endSec: nil) { ok in
                if ok { print("⬆️ Sent audio chunk (\(wav.count) bytes) for session \(sid)") }
                else { print("⚠️ Failed to send audio chunk for session \(sid)") }
            }
        }
    }

    private func validateAudioSetup() -> Bool {
        // Check if audio input is available using modern API
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discoverySession.devices
        guard !devices.isEmpty else {
            print("❌ No audio input devices available")
            return false
        }
        
        // Ensure the audio engine is properly initialized
        // AVAudioEngine should always have input/output nodes on macOS
        
        // Check if we have permission to access audio
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authStatus {
        case .authorized:
            print("✅ Audio permission granted")
        case .denied, .restricted:
            print("❌ Audio permission denied or restricted")
            return false
        case .notDetermined:
            print("⚠️ Audio permission not determined - requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print(granted ? "✅ Audio permission granted" : "❌ Audio permission denied")
            }
            return false
        @unknown default:
            print("⚠️ Unknown audio permission status")
            return false
        }
        
        // Validate audio engine state
        guard !engine.isRunning else {
            print("❌ Audio engine is already running")
            return false
        }
        
        print("✅ Audio setup validation passed")
        return true
    }
    
    private func resetAudioEngine() {
        print("🔄 Resetting audio engine...")
        
        // Stop and reset the current engine
        if engine.isRunning {
            engine.stop()
        }
        
        // Remove any existing taps
        engine.inputNode.removeTap(onBus: 0)
        
        // Reset converter
        converter = nil
        targetFormat = nil
        
        // Create a fresh engine instance
        let newEngine = AVAudioEngine()
        
        // Replace the engine
        engine = newEngine
        
        print("✅ Audio engine reset complete")
    }
    
    private func handleAudioDeviceChange() {
        // Monitor for audio device changes (e.g., headphones plugged/unplugged)
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔌 Audio device connected - revalidating setup")
            Task { @MainActor in
                _ = self?.validateAudioSetup()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔌 Audio device disconnected")
            Task { @MainActor in
                if self?.isRunning == true {
                    print("⚠️ Audio device disconnected while recording - stopping")
                    self?.stopListening {}
                }
            }
        }
    }
    
    private func wavData(fromPCM16 pcm: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * channels * 2
        let blockAlign: UInt16 = UInt16(channels * 2)
        let bitsPerSample: UInt16 = 16
        let subchunk2Size = UInt32(pcm.count)
        let chunkSize = 36 + subchunk2Size

        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(chunkSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData) // PCM header size
        data.append(UInt16(1).littleEndianData)  // PCM format
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(blockAlign.littleEndianData)
        data.append(bitsPerSample.littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(subchunk2Size.littleEndianData)
        data.append(pcm)
        return data
    }
}

private extension UInt16 {
    var littleEndianData: Data { withUnsafeBytes(of: self.littleEndian) { Data($0) } }
}

private extension UInt32 {
    var littleEndianData: Data { withUnsafeBytes(of: self.littleEndian) { Data($0) } }
}


