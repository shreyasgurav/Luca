import Foundation

struct DeepgramConfig {
    // Audio processing configuration - optimized for real-time
    static let targetSampleRate: Double = 16000.0
    static let channels: UInt32 = 1
    static let chunkDurationMs: Double = 25.0 // Reduced for faster processing
    
    // Calculated values
    static var chunkSizeFrames: Int {
        return Int(targetSampleRate * chunkDurationMs / 1000.0)
    }
    
    static var chunkSizeBytes: Int {
        return chunkSizeFrames * MemoryLayout<Int16>.size
    }
    
    // Deepgram API configuration
    static var deepgramApiKey: String? {
        // Try UserDefaults (set by APIKeyManager)
        if let storedKey = UserDefaults.standard.string(forKey: "DeepgramAPIKey"), !storedKey.isEmpty {
            return storedKey
        }
        
        // Try environment variable
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        
        return nil
    }
    
    static var apiKey: String {
        return deepgramApiKey ?? ""
    }
    
    // Audio quality settings
    static let bitsPerSample: UInt16 = 16
    static let audioFormat: String = "wav"
    
    // Buffer management
    static let maxBufferDurationSeconds: Double = 30.0
    static let bufferCleanupIntervalSeconds: Double = 5.0
    
    // WebSocket settings
    static let webSocketTimeoutSeconds: TimeInterval = 30.0
    static let reconnectDelaySeconds: TimeInterval = 2.0
    static let maxReconnectAttempts: Int = 3
    
    // Transcription settings
    static let transcriptionLanguage = "en"
    static let enablePunctuation = true
    static let enableSmartFormatting = true
    static let enableFillerWords = false
    static let enableDiarization = false
}