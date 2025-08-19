import Foundation
import Network

// MARK: - WebSocket Message Types

enum ListenMessageType: String, Codable {
    case startSession = "start_session"
    case audioChunk = "audio_chunk"
    case stopSession = "stop_session"
}

enum ListenResponseType: String, Codable {
    case sessionStarted = "session_started"
    case transcriptionUpdate = "transcription_update"
    case chunkAcknowledged = "chunk_acknowledged"
    case sessionCompleted = "session_completed"
    case error = "error"
}

// MARK: - Message Structures

struct ListenStartMessage: Codable {
    let type: ListenMessageType
    let sessionId: String?
}

struct ListenAudioChunkMessage: Codable {
    let type: ListenMessageType
    let sessionId: String
    let audioData: String // base64 encoded
    let chunkIndex: Int
}

struct ListenStopMessage: Codable {
    let type: ListenMessageType
    let sessionId: String
}

struct ListenResponse: Codable {
    let type: ListenResponseType
    let sessionId: String?
    let status: String?
    let text: String?
    let fullTranscript: String?
    let finalTranscript: String?
    let duration: Int?
    let totalChunks: Int?
    let stats: [String: String]?
    let error: String?
    let details: String?
    
    private enum CodingKeys: String, CodingKey {
        case type, sessionId, status, text, fullTranscript, finalTranscript, duration, totalChunks, stats, error, details
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ListenResponseType.self, forKey: .type)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        fullTranscript = try container.decodeIfPresent(String.self, forKey: .fullTranscript)
        finalTranscript = try container.decodeIfPresent(String.self, forKey: .finalTranscript)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        totalChunks = try container.decodeIfPresent(Int.self, forKey: .totalChunks)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        
        // Decode stats flexibly: either [String:String] or [String:Int]
        if let stringStats = try? container.decodeIfPresent([String: String].self, forKey: .stats) {
            stats = stringStats
        } else if let intStats = try? container.decodeIfPresent([String: Int].self, forKey: .stats) {
            stats = intStats.mapValues { String($0) }
        } else {
            stats = nil
        }
    }
}

// MARK: - WebSocket Listen API

@MainActor
final class ListenAPI: NSObject {
    static let shared = ListenAPI()
    
    private var webSocket: URLSessionWebSocketTask?
    private var sessionId: String?
    private var isConnected = false
    private var isStopping = false // NEW: Track if session is being stopped
    private var chunkIndex = 0
    
    // Callbacks
    var onTranscriptionUpdate: ((String, String) -> Void)?
    var onSessionStarted: ((String) -> Void)?
    var onSessionCompleted: ((String, [String: String]?) -> Void)? // Updated back to match stats field type
    var onError: ((String) -> Void)?
    var onSessionFinished: (() -> Void)? // NEW: Callback for when session is finished
    
    private override init() {
        super.init()
    }
    
    // MARK: - WebSocket Connection
    
    func connect() {
        guard let url = URL(string: "ws://localhost:3000/ws") else {
            onError?("Invalid WebSocket URL")
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        
        webSocket?.resume()
        receiveMessage()
        
        print("🔌 WebSocket connecting to \(url)")
    }
    
    func disconnect() {
        webSocket?.cancel()
        webSocket = nil
        isConnected = false
        isStopping = false // NEW: Clear stopping flag
        // NEW: Don't clear sessionId immediately - wait for session completion
        // sessionId = nil
        chunkIndex = 0
        print("🔌 WebSocket disconnected")
        
        // NEW: Clear session ID after a delay to allow final messages to be processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sessionId = nil
            print("🔌 Session ID cleared")
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            DispatchQueue.main.async {
                self?.handleMessage(result)
            }
        }
    }
    
    private func handleMessage(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleTextMessage(text)
            case .data(let data):
                handleDataMessage(data)
            @unknown default:
                print("⚠️ Unknown WebSocket message type")
            }
        case .failure(let error):
            print("❌ WebSocket receive error: \(error)")
            onError?("WebSocket error: \(error.localizedDescription)")
        }
        
        // Continue receiving messages
        receiveMessage()
    }
    
    private func handleTextMessage(_ text: String) {
        print("🔍 DEBUG: Received WebSocket text message: \(text.prefix(100))...")
        
        do {
            let data = text.data(using: .utf8) ?? Data()
            let response = try JSONDecoder().decode(ListenResponse.self, from: data)
            print("✅ Successfully decoded WebSocket message of type: \(response.type)")
            handleResponse(response)
        } catch {
            print("❌ Failed to decode WebSocket message: \(text)")
            print("🔍 DEBUG: Decoding error: \(error)")
            
            // Try to decode as a basic JSON to see what we're getting
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🔍 DEBUG: Raw JSON content: \(json)")
            }
        }
    }
    
    private func handleDataMessage(_ data: Data) {
        print("🔍 DEBUG: Received WebSocket data message: \(data.count) bytes")
        
        do {
            let response = try JSONDecoder().decode(ListenResponse.self, from: data)
            print("✅ Successfully decoded WebSocket data message of type: \(response.type)")
            handleResponse(response)
        } catch {
            print("❌ Failed to decode WebSocket data message")
            print("🔍 DEBUG: Decoding error: \(error)")
            
            // Try to decode as a basic JSON to see what we're getting
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🔍 DEBUG: Raw JSON content: \(json)")
            }
        }
    }
    
    private func handleResponse(_ response: ListenResponse) {
        switch response.type {
        case .sessionStarted:
            if let sid = response.sessionId {
                sessionId = sid
                isConnected = true
                onSessionStarted?(sid)
                print("✅ WebSocket session started: \(sid)")
            }
            
        case .transcriptionUpdate:
            if let text = response.text, let fullTranscript = response.fullTranscript {
                onTranscriptionUpdate?(text, fullTranscript)
                print("📝 Transcription update: \(text)")
            }
            
        case .chunkAcknowledged:
            print("✅ Audio chunk acknowledged")
            
        case .sessionCompleted:
            if let finalTranscript = response.finalTranscript {
                var stats: [String: String] = [:]
                if let duration = response.duration { stats["duration"] = String(duration) }
                if let totalChunks = response.totalChunks { stats["totalChunks"] = String(totalChunks) }
                
                onSessionCompleted?(finalTranscript, stats)
                print("✅ Session completed: \(finalTranscript.count) chars")
                
                // NEW: Call the session finished callback to trigger transcript saving
                onSessionFinished?()
                
                // NEW: Mark session as completed and disconnect
                print("✅ Session marked as completed")
                isStopping = false
                
                // NEW: Disconnect after processing session completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.disconnect()
                }
            }
            
        case .error:
            let errorMsg = response.error ?? "Unknown error"
            onError?(errorMsg)
            print("❌ WebSocket error: \(errorMsg)")
        }
    }
    
    // MARK: - Session Management
    
    func startSession() {
        guard webSocket != nil else {
            connect()
            // Wait a bit for connection, then start session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startSession()
            }
            return
        }
        
        let message = ListenStartMessage(type: .startSession, sessionId: nil)
        sendMessage(message)
        print("🎬 Starting WebSocket session")
    }
    
    func sendAudioChunk(audioData: Data) {
        guard let sid = sessionId, isConnected else {
            print("⚠️ No active session for audio chunk")
            return
        }
        
        let base64Audio = audioData.base64EncodedString()
        let message = ListenAudioChunkMessage(
            type: .audioChunk,
            sessionId: sid,
            audioData: base64Audio,
            chunkIndex: chunkIndex
        )
        
        sendMessage(message)
        chunkIndex += 1
    }
    
    func stopSession() {
        guard let sid = sessionId, isConnected else {
            print("⚠️ No active session to stop")
            return
        }
        
        isStopping = true // NEW: Mark session as stopping
        let message = ListenStopMessage(type: .stopSession, sessionId: sid)
        sendMessage(message)
        print("🛑 Stopping WebSocket session")
        
        // NEW: Wait for server response before disconnecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            // If still stopping after timeout, force disconnect
            if self?.isStopping == true {
                print("⏰ Timeout waiting for session completion, forcing disconnect")
                self?.disconnect()
            }
        }
    }
    
    // MARK: - Message Sending
    
    private func sendMessage<T: Codable>(_ message: T) {
        guard let data = try? JSONEncoder().encode(message),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to encode message")
            return
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket?.send(wsMessage) { error in
            if let error = error {
                print("❌ Failed to send WebSocket message: \(error)")
            }
        }
    }
}

// MARK: - Legacy HTTP API (for backward compatibility)

extension ListenAPI {
    func startSessionHTTP(completion: @escaping (Result<String, Error>) -> Void) {
        // Fallback to HTTP if WebSocket fails
        ClientAPI.shared.listenStart { result in
            completion(result)
        }
    }
    
    func sendChunkHTTP(sessionId: String, audioData: Data, completion: @escaping (Bool) -> Void) {
        ClientAPI.shared.listenSendChunk(sessionId: sessionId, audioData: audioData, startSec: nil, endSec: nil) { success in
            completion(success)
        }
    }
    
    func stopSessionHTTP(sessionId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        ClientAPI.shared.listenStop(sessionId: sessionId) { result in
            completion(result)
        }
    }
}


