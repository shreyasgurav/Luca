import Foundation
import Network

class ListenAPI: NSObject, ObservableObject {
    static let shared = ListenAPI()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var currentSessionId: String?
    private var chunkIndex = 0
    
    // Callbacks
    var onSessionStarted: ((String) -> Void)?
    var onTranscriptionUpdate: ((String, String) -> Void)?
    var onSessionCompleted: ((String, [String: String]?) -> Void)?
    var onError: ((String) -> Void)?
    
    private override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func connect() {
        guard !isConnected else { return }
        
        let baseURL = AppConfig.serverBaseURL.absoluteString
        let wsURL = baseURL.replacingOccurrences(of: "https://", with: "wss://")
                          .replacingOccurrences(of: "http://", with: "ws://")
        
        guard let url = URL(string: "\(wsURL)/ws") else {
            onError?("Invalid WebSocket URL")
            return
        }
        
        print("🔌 Connecting to WebSocket: \(url)")
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start listening for messages
        receiveMessage()
    }
    
    func disconnect() {
        guard isConnected else { return }
        
        print("🔌 Disconnecting WebSocket")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        currentSessionId = nil
        chunkIndex = 0
    }
    
    func startSession(sessionId: String? = nil) {
        guard isConnected else {
            connect()
            // Retry after connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startSession(sessionId: sessionId)
            }
            return
        }
        
        let message = [
            "type": "start_session",
            "sessionId": sessionId as Any
        ]
        
        sendMessage(message)
    }
    
    func sendAudioChunk(_ audioData: Data) {
        guard let sessionId = currentSessionId else {
            onError?("No active session")
            return
        }
        
        let base64Audio = audioData.base64EncodedString()
        let message: [String: Any] = [
            "type": "audio_chunk",
            "sessionId": sessionId,
            "audioData": base64Audio,
            "chunkIndex": chunkIndex
        ]
        
        sendMessage(message)
        chunkIndex += 1
    }
    
    func stopSession() {
        guard let sessionId = currentSessionId else {
            onError?("No active session")
            return
        }
        
        let message = [
            "type": "stop_session",
            "sessionId": sessionId
        ]
        
        sendMessage(message)
    }
    
    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else {
            onError?("Failed to serialize message")
            return
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                print("❌ WebSocket send error: \(error)")
                self?.onError?("Failed to send message: \(error.localizedDescription)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue listening
                self?.receiveMessage()
                
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                self?.onError?("Connection error: \(error.localizedDescription)")
                self?.isConnected = false
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                onError?("Invalid message format")
                return
            }
            
            handleJSONMessage(json)
            
        case .data(let data):
            // Handle binary data if needed
            print("📦 Received binary data: \(data.count) bytes")
            
        @unknown default:
            print("❓ Unknown message type")
        }
    }
    
    private func handleJSONMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else {
            if let error = json["error"] as? String {
                onError?(error)
            }
            return
        }
        
        print("📨 Received: \(type)")
        
        switch type {
        case "session_started":
            if let sessionId = json["sessionId"] as? String {
                currentSessionId = sessionId
                chunkIndex = 0
                print("🎤 Session started: \(sessionId)")
                onSessionStarted?(sessionId)
            }
            
        case "transcription_update":
            if let text = json["text"] as? String,
               let fullTranscript = json["fullTranscript"] as? String {
                print("🎯 Transcription: \(text)")
                onTranscriptionUpdate?(text, fullTranscript)
            }
            
        case "chunk_acknowledged":
            // Chunk processed successfully
            break
            
        case "session_completed":
            if let sessionId = json["sessionId"] as? String {
                let stats = json["stats"] as? [String: String]
                print("🛑 Session completed: \(sessionId)")
                onSessionCompleted?(sessionId, stats)
                currentSessionId = nil
                chunkIndex = 0
            }
            
        default:
            print("❓ Unknown message type: \(type)")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension ListenAPI: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
        isConnected = true
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket disconnected: \(closeCode)")
        isConnected = false
        currentSessionId = nil
        chunkIndex = 0
    }
}

// MARK: - URLSessionDelegate
extension ListenAPI: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // For development/testing - accept self-signed certificates
        if AppConfig.environment == .development {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}