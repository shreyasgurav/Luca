import Foundation
import Network
import Combine

/// Deepgram STT result model
struct DeepgramResult {
    let transcript: String
    let isFinal: Bool
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let channel: Int
    
    var isEmpty: Bool {
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Deepgram connection state
enum DeepgramConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(Error)
    case finalized
    
    static func == (lhs: DeepgramConnectionState, rhs: DeepgramConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.finalized, .finalized):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

/// Deepgram errors
enum DeepgramError: LocalizedError {
    case invalidAPIKey
    case connectionFailed(String)
    case authenticationFailed
    case networkError(Error)
    case invalidResponse(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Deepgram API key. Please check your configuration."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed. Please verify your Deepgram API key."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let response):
            return "Invalid response from Deepgram: \(response)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}

/// Professional Deepgram STT WebSocket client
@MainActor
final class DeepgramSTT: ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: DeepgramConnectionState = .disconnected
    @Published var isConnected: Bool = false
    @Published var liveTranscript: String = ""
    @Published var error: DeepgramError?
    
    // MARK: - Callbacks
    var onTranscriptResult: ((DeepgramResult) -> Void)?
    var onConnectionStateChange: ((DeepgramConnectionState) -> Void)?
    var onError: ((DeepgramError) -> Void)?
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var keepAliveTimer: Timer?
    private let session: URLSession
    private var currentUtterance: String = ""
    private var accumulatedTranscript: String = ""
    
    // Configuration
    private let apiKey = DeepgramConfig.apiKey
    private let streamingURL = DeepgramConfig.streamingURL
    private let keepAliveInterval = DeepgramConfig.keepAliveInterval
    
    // MARK: - Initialization
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = DeepgramConfig.connectionTimeout
        config.timeoutIntervalForResource = DeepgramConfig.connectionTimeout
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        // Best-effort cleanup without async in deinit
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    // MARK: - Public Interface
    
    /// Connect to Deepgram WebSocket
    func connect() async throws {
        guard DeepgramConfig.isConfigured else {
            let error = DeepgramError.configurationError("Deepgram API key not configured")
            await handleError(error)
            throw error
        }
        
        guard webSocketTask == nil else {
            print("⚠️ Deepgram: Already connected or connecting")
            return
        }
        
        await updateConnectionState(.connecting)
        
        do {
            try await establishConnection()
            await updateConnectionState(.connected)
            startKeepAlive()
            startReceiving()
            print("✅ Deepgram: Connected successfully")
        } catch {
            let deepgramError = error as? DeepgramError ?? .networkError(error)
            await handleError(deepgramError)
            throw deepgramError
        }
    }
    
    /// Send audio data to Deepgram
    func sendAudioData(_ audioData: Data) {
        guard let webSocketTask = webSocketTask,
              connectionState == .connected else {
            print("⚠️ Deepgram: Cannot send audio - not connected")
            return
        }
        
        webSocketTask.send(.data(audioData)) { [weak self] error in
            if let error = error {
                print("❌ Deepgram: Failed to send audio data: \(error)")
                Task { @MainActor in
                    await self?.handleError(.networkError(error))
                }
            }
        }
    }
    
    /// Finalize the stream and close connection
    func finalizeAndDisconnect() async {
        guard webSocketTask != nil else { return }
        
        print("🔄 Deepgram: Finalizing stream...")
        
        // Send finalize message to flush any remaining audio
        await sendControlMessage(type: "Finalize")
        
        // Give a moment for the server to process
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Send close stream message
        await sendControlMessage(type: "CloseStream")
        
        // Disconnect
        await disconnect()
    }
    
    /// Disconnect from Deepgram
    func disconnect() async {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        await updateConnectionState(.disconnected)
        print("✅ Deepgram: Disconnected")
    }
    
    // MARK: - Private Methods
    
    private func establishConnection() async throws {
        // Build WebSocket URL with parameters
        guard var components = URLComponents(string: streamingURL) else {
            throw DeepgramError.configurationError("Invalid streaming URL")
        }
        
        components.query = DeepgramConfig.queryString
        
        guard let url = components.url else {
            throw DeepgramError.configurationError("Failed to build streaming URL")
        }
        
        // Create WebSocket request with auth header
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = DeepgramConfig.connectionTimeout
        
        // Create WebSocket task
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        print("🔄 Deepgram: Connecting to \(url)")
    }
    
    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                await self?.handleWebSocketMessage(result)
                // Continue receiving
                self?.startReceiving()
            }
        }
    }
    
    private func handleWebSocketMessage(_ result: Result<URLSessionWebSocketTask.Message, Error>) async {
        switch result {
        case .success(let message):
            await processMessage(message)
            
        case .failure(let error):
            print("❌ Deepgram WebSocket error: \(error)")
            await handleError(.networkError(error))
        }
    }
    
    private func processMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            await handleJSONMessage(text)
            
        case .data(let data):
            print("📊 Deepgram: Received binary data (\(data.count) bytes)")
            
        @unknown default:
            print("⚠️ Deepgram: Unknown message type")
        }
    }
    
    private func handleJSONMessage(_ jsonString: String) async {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            await processDeepgramResponse(response)
        } catch {
            print("❌ Deepgram: Failed to decode response: \(error)")
            print("Raw response: \(jsonString)")
        }
    }
    
    private func processDeepgramResponse(_ response: DeepgramResponse) async {
        switch response.type {
        case "Results":
            await handleTranscriptResults(response)
            
        case "Metadata":
            print("📊 Deepgram metadata: \(String(describing: response.metadata))")
            
        case "SpeechStarted":
            print("🎤 Speech started")
            
        case "UtteranceEnd":
            print("⏸️ Utterance ended")
            
        case "Error":
            if let errorMessage = response.error {
                await handleError(.invalidResponse(errorMessage))
            }
            
        default:
            print("📝 Deepgram: Unknown message type: \(response.type ?? "unknown")")
        }
    }
    
    private func handleTranscriptResults(_ response: DeepgramResponse) async {
        guard let channel = response.channel?.alternatives?.first else { return }
        
        let transcript = channel.transcript ?? ""
        let isFinal = response.isFinal ?? response.speechFinal ?? false
        let confidence = channel.confidence ?? 0.0
        
        // Skip empty transcripts
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let result = DeepgramResult(
            transcript: transcript,
            isFinal: isFinal,
            startTime: response.start ?? 0.0,
            endTime: (response.start ?? 0.0) + (response.duration ?? 0.0),
            confidence: confidence,
            channel: 0
        )
        
        // Update live transcript
        if isFinal {
            accumulatedTranscript += " " + transcript
            currentUtterance = ""
        } else {
            currentUtterance = transcript
        }
        
        liveTranscript = (accumulatedTranscript + " " + currentUtterance).trimmingCharacters(in: .whitespaces)
        
        // Notify callback
        onTranscriptResult?(result)
        
        print("📝 Deepgram: \(isFinal ? "Final" : "Interim") - '\(transcript)' (confidence: \(String(format: "%.2f", confidence)))")
    }
    
    private func startKeepAlive() {
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendControlMessage(type: "KeepAlive")
            }
        }
    }
    
    private func sendControlMessage(type: String) async {
        guard let webSocketTask = webSocketTask else { return }
        
        let message = ["type": type]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            
            webSocketTask.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ Deepgram: Failed to send \(type): \(error)")
                }
            }
        } catch {
            print("❌ Deepgram: Failed to encode \(type) message: \(error)")
        }
    }
    
    private func updateConnectionState(_ state: DeepgramConnectionState) async {
        connectionState = state
        isConnected = (state == .connected)
        onConnectionStateChange?(state)
    }
    
    private func handleError(_ error: DeepgramError) async {
        self.error = error
        await updateConnectionState(.error(error))
        onError?(error)
        print("❌ Deepgram error: \(error.localizedDescription)")
    }
    
    // MARK: - Helper Methods
    
    /// Clear accumulated transcript
    func clearTranscript() {
        accumulatedTranscript = ""
        currentUtterance = ""
        liveTranscript = ""
    }
    
    /// Get connection status description
    var connectionStatusDescription: String {
        switch connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        case .finalized:
            return "Finalized"
        }
    }
}

// MARK: - Deepgram Response Models

private struct DeepgramResponse: Codable {
    let type: String?
    let channel: DeepgramChannel?
    let isFinal: Bool?
    let speechFinal: Bool?
    let start: Double?
    let duration: Double?
    let metadata: DeepgramMetadata?
    let error: String?
    
    private enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case start
        case duration
        case metadata
        case error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        type = try container.decodeIfPresent(String.self, forKey: .type)
        isFinal = try container.decodeIfPresent(Bool.self, forKey: .isFinal)
        speechFinal = try container.decodeIfPresent(Bool.self, forKey: .speechFinal)
        start = try container.decodeIfPresent(Double.self, forKey: .start)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        metadata = try container.decodeIfPresent(DeepgramMetadata.self, forKey: .metadata)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        
        // Handle channel which can be either an object or array
        if let channelValue = try? container.decodeIfPresent(DeepgramChannel.self, forKey: .channel) {
            channel = channelValue
        } else {
            // If channel is not a DeepgramChannel object, try to decode it as an array or other type
            // This handles cases like "channel":[0,1] in SpeechStarted messages
            _ = try? container.decodeIfPresent(AnyCodable.self, forKey: .channel)
            channel = nil
        }
    }
}

// Helper struct to handle any JSON value
private struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        let container = encoder.singleValueContainer()
        throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable cannot encode value"))
    }
}

private struct DeepgramChannel: Codable {
    let alternatives: [DeepgramAlternative]?
}

private struct DeepgramAlternative: Codable {
    let transcript: String?
    let confidence: Double?
    let words: [DeepgramWord]?
}

private struct DeepgramWord: Codable {
    let word: String?
    let start: Double?
    let end: Double?
    let confidence: Double?
}

private struct DeepgramMetadata: Codable {
    let requestId: String?
    let modelInfo: DeepgramModelInfo?
    
    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case modelInfo = "model_info"
    }
}

private struct DeepgramModelInfo: Codable {
    let name: String?
    let version: String?
    let arch: String?
    let languages: [String]?
}
