import Foundation

enum AnalyzeAPI {
    static func upload(imageData: Data, includeOCR: Bool, sessionId: String?, prompt: String?, completion: @escaping (Result<String, Error>) -> Void) {
        ClientAPI.shared.uploadAndAnalyze(imageData: imageData, includeOCR: includeOCR, sessionId: sessionId, customPrompt: prompt, completion: completion)
    }
}


