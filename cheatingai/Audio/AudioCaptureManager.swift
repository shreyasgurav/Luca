import Foundation
import AVFoundation
import AppKit

@MainActor
final class AudioCaptureManager: NSObject {
    static let shared = AudioCaptureManager()

    private let engine = AVAudioEngine()
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
        setupAudioSession()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        // Target: PCM 16-bit, mono, 16kHz (non-interleaved so int16ChannelData is available)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            onStarted(false); return
        }
        targetFormat = target
        converter = AVAudioConverter(from: inputFormat, to: target)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Feed Apple Speech with original input stream for local transcription
            // Ensure mono 16k for recognizer if needed; otherwise pass original
            SpeechTranscriber.shared.append(buffer)
            self.handleIncoming(buffer: buffer)
        }

        do {
            try engine.start()
            isRunning = true
            print("🎧 AudioCaptureManager: engine started, sampleRate=\(inputFormat.sampleRate), ch=\(inputFormat.channelCount)")
            lastNonSilenceAt = Date()
            didWarnNoAudio = false
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
            onStarted(true)
        } catch {
            print("❌ AudioCaptureManager: engine.start failed: \(error.localizedDescription)")
            onStarted(false)
        }
    }

    func stopListening(completion: @escaping () -> Void) {
        guard isRunning else { completion(); return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        didWarnNoAudio = false
        didLaunchGuides = false

        // Flush remaining chunk if any
        if accumulatedSamples > 0, let sid = sessionId {
            let wav = self.wavData(fromPCM16: accumulatingPCM, sampleRate: Int(targetSampleRate), channels: 1)
            ClientAPI.shared.listenSendChunk(sessionId: sid, audioData: wav, startSec: nil, endSec: nil) { _ in }
        }

        completion()
    }

    private func setupAudioSession() {
        #if os(macOS)
        // macOS: AVAudioSession is unavailable; AVAudioEngine works without explicit session config.
        return
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

        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(buffer.frameLength)) else { return }
        var error: NSError?
        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        if error != nil { return }

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


