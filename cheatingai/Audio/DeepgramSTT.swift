import Foundation
import os.log

protocol DeepgramSTTDelegate: AnyObject {
    func didReceiveTranscription(_ text: String, isFinal: Bool, confidence: Float)
    func didReceiveError(_ error: Error)
    func didConnect()
    func didDisconnect()
}

class DeepgramSTT: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.cheating.cheatingai", category: "DeepgramSTT")
    
    weak var delegate: DeepgramSTTDelegate?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    
    // WebSocket state and buffering
    private enum WSState { case idle, connecting, open, closing, closed }
    private var state: WSState = .idle
    private var pendingChunks: [Data] = []
    private let maxPendingChunks = 200
    private var pingTimer: Timer?
    
    // Debug counters
    private var audioDataSentCount = 0
    private var transcriptionReceivedCount = 0
    private var connectionAttempts = 0
    
    @Published var isConnected = false
    @Published var lastTranscription = ""
    @Published var connectionStatus = "Disconnected"
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 0 // No timeout for WebSocket
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func connect() {
        let apiKey = DeepgramConfig.apiKey
        guard !apiKey.isEmpty else {
            logger.error("❌ No Deepgram API key found")
            return
        }
        
        connectionAttempts += 1
        logger.info("🔄 Connection attempt #\(self.connectionAttempts)")
        
        // Enhanced WebSocket URL with better parameters
        var urlComponents = URLComponents()
        urlComponents.scheme = "wss"
        urlComponents.host = "api.deepgram.com"
        urlComponents.path = "/v1/listen"
        
        urlComponents.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "endpointing", value: "300")
        ]
        
        guard let url = urlComponents.url else {
            logger.error("❌ Failed to create WebSocket URL")
            return
        }
        
        logger.info("🔗 Connecting to: \(url)")
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("YourApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()
        state = .connecting
        
        DispatchQueue.main.async {
            self.connectionStatus = "Connecting..."
        }
        
        // Start listening for messages immediately
        receiveMessage()
    }
    
    func disconnect() {
        logger.info("🔄 Disconnecting WebSocket...")
        
        // Send close frame gracefully
        pingTimer?.invalidate(); pingTimer = nil
        state = .closing
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
        }
        
        delegate?.didDisconnect()
    }
    
    func sendAudioData(_ audioData: Data) {
        guard let webSocket = webSocket else {
            logger.error("❌ WebSocket is nil")
            return
        }
        
        guard state == .open else {
            if pendingChunks.count >= maxPendingChunks { pendingChunks.removeFirst() }
            pendingChunks.append(audioData)
            logger.debug("🔒 Queued audio chunk (WS not open). pending=\(self.pendingChunks.count)")
            return
        }
        
        audioDataSentCount += 1
        webSocket.send(.data(audioData)) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending audio: \(error)")
                self?.state = .closed
            } else if let count = self?.audioDataSentCount, count % 100 == 0 {
                self?.logger.debug("📤 Audio sent #\(count)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue listening for more messages
                self?.receiveMessage()
                
            case .failure(let error):
                self?.logger.error("❌ WebSocket receive error: \(error)")
                self?.handleError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            transcriptionReceivedCount += 1
            logger.debug("📝 Received message #\(self.transcriptionReceivedCount)")
            parseDeepgramResponse(text)
            
        case .data(let data):
            logger.debug("📦 Received binary data: \(data.count) bytes")
            
        @unknown default:
            logger.warning("⚠️ Unknown message type")
        }
    }
    
    private func parseDeepgramResponse(_ jsonString: String) {
        logger.debug("📄 Raw response: \(jsonString)")
        
        guard let data = jsonString.data(using: .utf8) else {
            logger.error("❌ Failed to convert response to data")
            return
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("❌ Invalid JSON structure")
                return
            }
            
            // Log all top-level keys for debugging
            logger.debug("🔍 JSON keys: \(Array(json.keys))")
            
            // Handle different response types
            if let type = json["type"] as? String {
                logger.info("📋 Response type: \(type)")
                
                switch type {
                case "Results":
                    handleResultsResponse(json)
                case "UtteranceEnd":
                    logger.info("🏁 Utterance ended")
                case "SpeechStarted":
                    logger.info("🎤 Speech started")
                case "Metadata":
                    if let metadata = json["metadata"] as? [String: Any] {
                        logger.info("📊 Metadata: \(metadata)")
                    }
                default:
                    logger.warning("❓ Unknown response type: \(type)")
                }
            } else {
                // Some responses might not have a 'type' field
                logger.debug("📝 Response without type field")
                
                // Check if this is a results response without explicit type
                if json["channel"] != nil {
                    handleResultsResponse(json)
                }
            }
            
        } catch {
            logger.error("❌ JSON parsing error: \(error)")
            logger.error("Raw JSON: \(jsonString)")
        }
    }
    
    private func handleResultsResponse(_ json: [String: Any]) {
        logger.debug("🔍 Processing Results response")
        
        guard let channel = json["channel"] as? [String: Any] else {
            logger.warning("⚠️ No 'channel' in Results response")
            return
        }
        
        guard let alternatives = channel["alternatives"] as? [[String: Any]], !alternatives.isEmpty else {
            logger.warning("⚠️ No alternatives in Results response")
            return
        }
        
        let firstAlternative = alternatives[0]
        let transcript = firstAlternative["transcript"] as? String ?? ""
        let confidence = (firstAlternative["confidence"] as? NSNumber)?.floatValue ?? 0.0
        let isFinal = json["is_final"] as? Bool ?? false
        
        logger.info("📝 Transcript: '\(transcript)' (confidence: \(confidence), final: \(isFinal))")
        
        // Update UI on main thread
        DispatchQueue.main.async {
            self.lastTranscription = transcript
        }
        
        // Don't process empty transcripts
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            delegate?.didReceiveTranscription(transcript, isFinal: isFinal, confidence: confidence)
        } else {
            logger.debug("📝 Empty transcript - not processing")
        }
    }
    
    private func handleError(_ error: Error) {
        logger.error("❌ Deepgram error: \(error)")
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Error: \(error.localizedDescription)"
        }
        
        delegate?.didReceiveError(error)
    }
}

// MARK: - URLSessionWebSocketDelegate
extension DeepgramSTT: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.info("✅ WebSocket connected")
        state = .open
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionStatus = "Connected"
        }
        
        // Drain pending buffered audio
        if !self.pendingChunks.isEmpty {
            self.logger.info("🚰 Draining \(self.pendingChunks.count) queued audio chunks")
            let chunks = self.pendingChunks
            self.pendingChunks.removeAll()
            for chunk in chunks { self.sendAudioData(chunk) }
        }
        
        // Start ping keep-alive
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .open else { return }
            self.webSocket?.sendPing { err in
                if let err = err { self.logger.error("❌ WebSocket ping failed: \(err.localizedDescription)") }
            }
        }
        
        delegate?.didConnect()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason?.count ?? 0 > 0 ? String(data: reason!, encoding: .utf8) ?? "Unknown" : "No reason"
        logger.info("🔌 WebSocket closed with code: \(closeCode.rawValue), reason: \(reasonString)")
        
        pingTimer?.invalidate(); pingTimer = nil
        state = .closed
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
        }
        
        delegate?.didDisconnect()
    }
    func finalizeAndDisconnect() {
        logger.info("🏁 Finalizing Deepgram session...")
        
        // Send finalize control message (lowercase per Deepgram docs)
        if state == .open {
            let finalizeMessage = ["type": "finalize"]
            if let jsonData = try? JSONSerialization.data(withJSONObject: finalizeMessage),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                webSocket?.send(.string(jsonString)) { [weak self] error in
                    if let error = error {
                        self?.logger.error("❌ Failed to send finalize message: \(error)")
                    }
                    self?.disconnect()
                }
                return
            }
        }
        disconnect()
    }
}

// MARK: - URLSessionDelegate
extension DeepgramSTT: URLSessionDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.error("❌ URLSession task completed with error: \(error)")
            handleError(error)
        }
        pingTimer?.invalidate(); pingTimer = nil
        state = .closed
    }
}
