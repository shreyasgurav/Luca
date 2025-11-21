import Foundation
import os.log

final class MultiSourceSTTManager: DeepgramSTTDelegate {
    private let logger = Logger(subsystem: "com.luca.app", category: "MultiSourceSTTManager")
    
    let systemSTT: DeepgramSTT
    let micSTT: DeepgramSTT
    
    init() {
        systemSTT = DeepgramSTT(source: .system)
        micSTT = DeepgramSTT(source: .microphone)
        
        systemSTT.delegate = self
        micSTT.delegate = self
    }
    
    func connectAll() {
        systemSTT.connect()
        micSTT.connect()
    }
    
    func disconnectAll() {
        systemSTT.finalizeAndDisconnect()
        micSTT.finalizeAndDisconnect()
    }
    
    func sendAudioData(_ data: Data, for source: DeepgramSTT.SourceType) {
        switch source {
        case .system:
            logger.debug("📡 Sending system audio data: \(data.count) bytes")
            systemSTT.sendAudioData(data)
        case .microphone:
            logger.debug("🎤 Sending microphone audio data: \(data.count) bytes")
            micSTT.sendAudioData(data)
        }
    }
    
    // MARK: - DeepgramSTTDelegate
    func didReceiveTranscription(_ text: String, isFinal: Bool, confidence: Float, source: DeepgramSTT.SourceType) {
        // Forward to the transcript store using its delegate-style API so partials update live bubble
        SessionTranscriptStore.shared.didReceiveTranscription(text, isFinal: isFinal, confidence: confidence, source: source)
    }
    
    func didReceiveError(_ error: Error, source: DeepgramSTT.SourceType) {
        logger.error("STT error (\(source.rawValue)): \(error.localizedDescription)")
    }
    
    func didConnect(source: DeepgramSTT.SourceType) {
        logger.info("\(source.rawValue) STT connected")
    }
    
    func didDisconnect(source: DeepgramSTT.SourceType) {
        logger.info("\(source.rawValue) STT disconnected")
    }
}


