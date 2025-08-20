import Foundation

/// Configuration for Deepgram STT integration
enum DeepgramConfig {
    /// Deepgram API Key - configure this with your actual key
    static let apiKey: String = {
        // Try environment variable first (for development)
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        
        // Fallback to hardcoded key (replace with your actual key)
        // TODO: Replace with your actual Deepgram API key
        return "18dee0aaa6dbf2446c3d2eece7816a21bb1cadc9"
    }()
    
    /// WebSocket URL for Deepgram streaming
    static let streamingURL = "wss://api.deepgram.com/v1/listen"
    
    /// Optimal parameters for Nova's use case
    static let streamingParameters: [String: String] = [
        "model": "nova-2",              // Latest high-accuracy model
        "encoding": "linear16",         // 16-bit PCM
        "sample_rate": "16000",         // 16kHz for optimal quality/bandwidth
        "channels": "1",                // Mono audio
        "smart_format": "true",         // Auto punctuation & formatting
        "interim_results": "true",      // Live results
        "endpointing": "1000",          // 1 second silence = utterance end
        "utterances": "true",           // Sentence-level results
        "vad_events": "true",           // Voice activity detection
        "punctuate": "true",            // Add punctuation
        "diarize": "false",             // Single speaker for system audio
        "multichannel": "false",        // Single channel processing
        "alternatives": "1",            // One transcription alternative
        "profanity_filter": "false",    // Don't filter profanity
        "redact": "false",              // Don't redact PII
        "ner": "false",                 // Don't need named entity recognition
        "search": "",                   // No search terms
        "replace": "",                  // No replacement terms
        "keywords": ""                  // No custom keywords
    ]
    
    /// Chunk size for streaming (50ms at 16kHz mono 16-bit = 1600 bytes)
    static let chunkSizeBytes = 1600
    
    /// Keep-alive interval to prevent connection timeout
    static let keepAliveInterval: TimeInterval = 5.0
    
    /// Connection timeout
    static let connectionTimeout: TimeInterval = 10.0
    
    /// Validate configuration
    static var isConfigured: Bool {
        return apiKey != "YOUR_DEEPGRAM_API_KEY_HERE" && !apiKey.isEmpty
    }
    
    /// Get query string for WebSocket URL
    static var queryString: String {
        return streamingParameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }
}
