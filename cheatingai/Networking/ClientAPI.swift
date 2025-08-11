import Foundation

struct AnalyzeResponse: Decodable {
    let assistant_text: String
}

final class ClientAPI {
    static let shared = ClientAPI()
    private init() {}

    var baseURL: URL = URL(string: "http://localhost:3000")!

    func uploadAndAnalyze(imageData: Data, includeOCR: Bool, sessionId: String?, customPrompt: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let endpoint = baseURL.appendingPathComponent("/api/analyze")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 80 // 1 minute + buffer for screenshot analysis

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // image
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")

        // includeOCR
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"includeOCR\"\r\n\r\n")
        body.appendString(includeOCR ? "true" : "false")
        body.appendString("\r\n")

        // sessionId
        if let sessionId {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"sessionId\"\r\n\r\n")
            body.appendString(sessionId)
            body.appendString("\r\n")
        }
        
        // customPrompt
        if let customPrompt {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"promptContext\"\r\n\r\n")
            body.appendString(customPrompt)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
                
                // Store the screenshot analysis in vector memory system
                Task { @MainActor in
                    await VectorMemoryManager.shared.storeMessage(content: "Screenshot uploaded", role: "user", type: .screenshot)
                    await VectorMemoryManager.shared.storeMessage(content: decoded.assistant_text, role: "assistant", type: .analysis)
                }
                
                completion(.success(decoded.assistant_text))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func chat(message: String, sessionId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        // First, get relevant context from enhanced vector memory system
        Task { @MainActor in
            // ensure local session id is in sync with caller sessionId
            if let sessionId = sessionId, !sessionId.isEmpty {
                VectorMemoryManager.shared.currentSessionId = sessionId
            } else {
                // ensure manager has a sessionId (start one if missing)
                _ = VectorMemoryManager.shared.getCurrentSessionId()
            }
            
            let context = await VectorMemoryManager.shared.getRelevantMemoriesWithContext(for: message)
            
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "message": message,
                "sessionId": sessionId ?? "",
                "promptContext": context.isEmpty ? nil : context
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { completion(.failure(error)); return }
                guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
                do {
                    let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
                    
                    // Store the conversation in vector memory system
                    Task { @MainActor in
                        // Store messages in session
                        await VectorMemoryManager.shared.storeMessage(content: message, role: "user")
                        await VectorMemoryManager.shared.storeMessage(content: decoded.assistant_text, role: "assistant")
                        
                        // Extract and store important memories with embeddings
                        await self.extractAndStoreMemories(userMessage: message, assistantResponse: decoded.assistant_text)
                    }
                    
                    completion(.success(decoded.assistant_text))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }
    
    private func extractAndStoreMemories(userMessage: String, assistantResponse: String) async {
        // Store user information if it contains personal details
        if containsPersonalInfo(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .personal,
                source: .conversation,
                importance: 0.8
            )
        }
        
        // Store preferences if user expresses likes/dislikes
        if containsPreferences(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .preference,
                source: .conversation,
                importance: 0.7
            )
        }
        
        // Store goals and projects
        if containsGoals(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .goal,
                source: .conversation,
                importance: 0.75
            )
        }
        
        // Store instructions for how user wants to be helped
        if containsInstructions(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .instruction,
                source: .explicit,
                importance: 0.9
            )
        }
        
        // Store important facts shared by user
        if containsImportantFacts(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .knowledge,
                source: .conversation,
                importance: 0.6
            )
        }
    }
    
    // MARK: - Content Analysis Helpers
    
    private func containsPersonalInfo(_ text: String) -> Bool {
        let patterns = ["my name is", "i'm ", "i am ", "i live", "my birthday", "my age", "i work at", "i study"]
        return patterns.contains { text.lowercased().contains($0) }
    }
    
    private func containsPreferences(_ text: String) -> Bool {
        let patterns = ["i like", "i love", "i prefer", "i hate", "i don't like", "my favorite", "i enjoy"]
        return patterns.contains { text.lowercased().contains($0) }
    }
    
    private func containsGoals(_ text: String) -> Bool {
        let patterns = ["project", "goal", "want to", "planning to", "working on", "trying to", "hoping to", "deadline"]
        return patterns.contains { text.lowercased().contains($0) }
    }
    
    private func containsInstructions(_ text: String) -> Bool {
        let patterns = ["remember", "always", "never", "please", "help me", "remind me", "i need you to"]
        return patterns.contains { text.lowercased().contains($0) }
    }
    
    private func containsImportantFacts(_ text: String) -> Bool {
        let patterns = ["important", "fact", "information", "details", "know that", "tell you", "should know"]
        return patterns.contains { text.lowercased().contains($0) }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}


