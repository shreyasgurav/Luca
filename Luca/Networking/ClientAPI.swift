import Foundation
import FirebaseAuth

struct AnalyzeResponse: Decodable {
    let assistant_text: String?
    let structured: String?
    let openai_raw: String?
    
    // For mock responses from root endpoint
    let analysis: String?
    let ocr_text: String?
    let insights: [String]?
    let api_configured: Bool?
    
    // Computed property to handle both response formats
    var responseText: String {
        return assistant_text ?? analysis ?? "No response received"
    }
}

final class ClientAPI: @unchecked Sendable {
    static let shared = ClientAPI()
    private init() {}

    var baseURL: URL = AppConfig.serverBaseURL

    func uploadAndAnalyze(imageData: Data, includeOCR: Bool, sessionId: String?, customPrompt: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let endpoint = baseURL.appendingPathComponent("/api/analyze")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 80 // 1 minute + buffer for screenshot analysis
        
        // Add API key header for production
        if AppConfig.isCloudDeployed {
            request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
        }

        if AppConfig.isCloudDeployed {
            // Send JSON with base64 image to simplify serverless parsing on Vercel
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let base64 = imageData.base64EncodedString()
            var json: [String: Any] = [
                "image_base64": base64,
                "mime": "image/jpeg",
                "includeOCR": includeOCR,
                "sessionId": sessionId ?? ""
            ]
            if let customPrompt, !customPrompt.isEmpty { json["promptContext"] = customPrompt }
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
            print("🌐 Sending JSON analyze request to: \(endpoint)")
        } else {
            // Local dev: keep multipart path
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
            
            // customPrompt (store actual user question so context/memory have real text)
            if let customPrompt, !customPrompt.isEmpty {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"promptContext\"\r\n\r\n")
                body.appendString(customPrompt)
                body.appendString("\r\n")
            }

            body.appendString("--\(boundary)--\r\n")
            request.httpBody = body

            print("🌐 Sending request to: \(endpoint)")
            print("📊 Request body size: \(body.count) bytes")
            print("🔑 Boundary: \(boundary)")
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { 
                print("❌ Network error: \(error)")
                completion(.failure(error)); 
                return 
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Response: \(httpResponse.statusCode)")
                print("📡 Response headers: \(httpResponse.allHeaderFields)")
            }
            
            guard let data else { 
                print("❌ No response data")
                completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); 
                return 
            }
            
            print("📥 Received data: \(data.count) bytes")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Response content: \(responseString)")
            }
            
            do {
                let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
                print("✅ Successfully decoded response")
                // Store both the user prompt and analysis so context retrieval has the right text
                Task { @MainActor in
                    if let prompt = customPrompt, !prompt.isEmpty {
                        await VectorMemoryManager.shared.storeMessage(content: prompt, role: "user", type: .screenshot)
                    } else {
                        await VectorMemoryManager.shared.storeMessage(content: "Screenshot question", role: "user", type: .screenshot)
                    }
                                    await VectorMemoryManager.shared.storeMessage(content: decoded.responseText, role: "assistant", type: .analysis)
            }
            
            completion(.success(decoded.responseText))
            } catch {
                print("❌ JSON decode error: \(error)")
                print("❌ Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                completion(.failure(error))
            }
        }.resume()
    }

    func chat(message: String, sessionId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        // Check if transcript context is already included in the message
        let hasTranscriptContext = message.contains("[Current Meeting Context]") || message.contains("[Current Meeting Transcript]")
        
        print("🔍 ClientAPI.chat: hasTranscriptContext = \(hasTranscriptContext)")
        
        Task { @MainActor in
            // Only get vector context if transcript is not already included
            let context: String
            if hasTranscriptContext {
                print("⚡ ClientAPI.chat: Skipping vector memory search (transcript context detected)")
                context = ""
            } else {
                print("🔍 ClientAPI.chat: Getting vector memory context...")
                context = await VectorMemoryManager.shared.getRelevantMemoriesWithContext(for: message, sessionId: sessionId)
                print("📚 ClientAPI.chat: Vector context length: \(context.count) chars")
            }

            // Ambient context: local time
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d, yyyy h:mm a"
            let timeString = formatter.string(from: now)
            let tz = TimeZone.current
            let ambient = "Local Time: \(timeString) (\(tz.identifier), GMT\(tz.secondsFromGMT()/3600))"
            let ambientBlock = "[Ambient Context: \(ambient)]\n\n"
            
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add API key header for production
            if AppConfig.isCloudDeployed {
                request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
            }
            
            let promptContext: Any? = context.isEmpty ? nil : context
            let body: [String: Any] = [
                "message": ambientBlock + message,
                "sessionId": sessionId ?? "",
                "promptContext": promptContext as Any
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { completion(.failure(error)); return }
                guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
                do {
                    let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
                    
                    // Store the conversation in vector memory system (only if not using direct transcript context)
                    if !hasTranscriptContext {
                        Task { @MainActor in
                            // Store messages in session
                            await VectorMemoryManager.shared.storeMessage(content: message, role: "user")
                            await VectorMemoryManager.shared.storeMessage(content: decoded.responseText, role: "assistant")
                            
                            // Extract and store important memories with embeddings (gated)
                            await self.extractAndStoreMemories(userMessage: message, assistantResponse: decoded.responseText, sessionId: sessionId)
                        }
                    }
                    
                    completion(.success(decoded.responseText))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }

    // Chat without memory extraction - used for transcript content generation
    func chatWithoutMemoryExtraction(message: String, sessionId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 ClientAPI.chatWithoutMemoryExtraction: Skipping memory extraction for transcript processing")
        
        Task { @MainActor in
            // Skip vector memory search entirely for transcript content generation
            
            // For transcript-bound requests, avoid adding ambient context to preserve token budget
            let containsTranscriptMarker = message.contains("[Session Transcript]") || message.contains("[Current Meeting Transcript]") || message.contains("[Current Meeting Context]")
            let finalMessage: String
            if containsTranscriptMarker {
                finalMessage = message
            } else {
                let now = Date()
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, MMM d, yyyy h:mm a"
                let timeString = formatter.string(from: now)
                let tz = TimeZone.current
                let ambient = "Local Time: \(timeString) (\(tz.identifier), GMT\(tz.secondsFromGMT()/3600))"
                finalMessage = "[Ambient Context: \(ambient)]\n\n" + message
            }
            
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add API key header for production
            if AppConfig.isCloudDeployed {
                request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
            }
            
            let body: [String: Any] = [
                "message": finalMessage,
                "sessionId": sessionId ?? ""
                // No promptContext to avoid memory extraction
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { completion(.failure(error)); return }
                guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
                do {
                    let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
                    
                    // NO memory extraction - this is for transcript content generation only
                    print("✅ ClientAPI.chatWithoutMemoryExtraction: Response received without memory extraction")
                    
                    completion(.success(decoded.responseText))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }

    // Lightweight chat for inline overlay input: fetch memory context but skip heavy extraction
    func chatLite(message: String, sessionId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        Task { @MainActor in
            // Ensure session is synced
            if let sid = sessionId, !sid.isEmpty {
                VectorMemoryManager.shared.currentSessionId = sid
                SessionManager.shared.currentSessionId = sid
            } else {
                let sid = VectorMemoryManager.shared.getCurrentSessionId()
                SessionManager.shared.currentSessionId = sid
            }

            // Build memory+conversation context
            let ctx = await VectorMemoryManager.shared.getRelevantMemoriesWithContext(for: message, sessionId: sessionId)

            var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add API key header for production
            if AppConfig.isCloudDeployed {
                request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
            }
            
            let promptContext: Any? = ctx.isEmpty ? nil : ctx
            let body: [String: Any] = [
                "message": message,
                "sessionId": sessionId ?? "",
                "promptContext": promptContext as Any
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error { completion(.failure(error)); return }
                guard let data else {
                    completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
                    completion(.success(decoded.responseText))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }

    // MARK: - Listen API (HTTP Fallback)

    @MainActor
    func listenStart(preferredSource: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/api/listen/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add API key header for production
        if AppConfig.isCloudDeployed {
            request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let body: [String: Any] = [
            "preferredSource": preferredSource ?? "mic"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let sessionId = obj?["sessionId"] as? String { completion(.success(sessionId)) }
                else { completion(.failure(NSError(domain: "ClientAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing sessionId"])))}
            } catch { completion(.failure(error)) }
        }.resume()
    }

    func listenSendChunk(sessionId: String, audioData: Data, startSec: Int?, endSec: Int?, completion: @escaping (Bool) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/listen/chunk"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        
        // Add API key header for production
        if AppConfig.isCloudDeployed {
            request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"audio\"; filename=\"chunk.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        // Use uploadTask with 'from' and do NOT set httpBody to avoid double body stream
        URLSession.shared.uploadTask(with: request, from: body) { _, _, error in
            completion(error == nil)
        }.resume()
    }

    func listenStop(sessionId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/listen/stop"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        
        // Add API key header for production
        if AppConfig.isCloudDeployed {
            request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                // NEW: Extract and store server transcript (NO memory extraction)
                if let transcript = obj?["transcript"] as? String, !transcript.isEmpty {
                    Task { @MainActor in
                        SessionTranscriptStore.shared.addServerTranscript(transcript)
                        print("📝 Server transcript added: \(transcript.prefix(100))...")
                        // NO memory extraction from server transcripts
                        print("🚫 Skipping memory extraction for server transcript")
                    }
                }
                
                completion(.success(obj ?? [:]))
            } catch { completion(.failure(error)) }
        }.resume()
    }
    
    private func extractAndStoreMemories(userMessage: String, assistantResponse: String, sessionId: String?) async {
        // Use centralized gated extraction with session cooldown
        guard let sessionId = sessionId else { return }
        await VectorMemoryManager.shared.considerMemoryExtraction(
            userMessage: userMessage,
            assistantResponse: assistantResponse,
            sessionId: sessionId
        )
    }
    
    @MainActor
    private func extractMemoriesFromTranscript(content: String) async {
        do {
            let url = URL(string: "\(baseURL)/api/memory/extract-transcript")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add API key header for production
            if AppConfig.isCloudDeployed {
                request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
            }
            
            let payload = [
                "content": content,
                "userId": Auth.auth().currentUser?.uid ?? "unknown",
                "sessionId": VectorMemoryManager.shared.currentSessionId ?? ""
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            print("🧠 Extracting memories from transcript...")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let responseData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let success = responseData?["success"] as? Bool, success,
                   let extractedFacts = responseData?["extractedFacts"] as? [[String: Any]] {
                    
                    print("✅ Extracted \(extractedFacts.count) memories from transcript")
                    
                    // Store each extracted memory with proper embeddings
                    var storedAny = false
                    for fact in extractedFacts {
                        guard let text = fact["text"] as? String,
                              let kindString = fact["kind"] as? String,
                              let importance = fact["importance"] as? Double else { 
                            print("⚠️ Skipping malformed fact: \(fact)")
                            continue 
                        }
                        
                        let memoryType = mapStringToMemoryType(kindString)
                        
                        print("🔄 ClientAPI: About to store transcript memory:")
                        print("   - Text: \(text)")
                        print("   - Type: \(memoryType.rawValue)")
                        print("   - Importance: \(importance)")
                        
                        await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                            content: text,
                            type: memoryType,
                            source: .conversation,
                            importance: importance
                        )
                        storedAny = true
                    }
                    
                    if storedAny {
                        print("✅ Successfully stored memories from transcript")
                    } else {
                        print("📝 No memories to store from transcript")
                    }
                } else {
                    print("⚠️ Invalid response format from transcript memory extraction")
                }
            } else {
                print("❌ Failed to extract memories from transcript: HTTP \(response)")
            }
        } catch {
            print("❌ Error extracting memories from transcript: \(error)")
        }
    }

    @MainActor
    private func extractMemoriesFromServer(content: String) async {
        do {
            let url = URL(string: "\(baseURL)/api/memory/extract")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add API key header for production
            if AppConfig.isCloudDeployed {
                request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
            }
            
            let payload = [
                "content": content,
                "userId": Auth.auth().currentUser?.uid ?? "unknown",
                "sessionId": VectorMemoryManager.shared.currentSessionId ?? ""
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            print("🧠 Extracting memories from conversation...")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let responseData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let success = responseData?["success"] as? Bool, success,
                   let extractedFacts = responseData?["extractedFacts"] as? [[String: Any]] {
                    
                    print("✅ Extracted \(extractedFacts.count) memories from conversation")
                    
                    // Store each extracted memory with proper embeddings
                    var storedAny = false
                    for fact in extractedFacts {
                        guard let text = fact["text"] as? String,
                              let kindString = fact["kind"] as? String,
                              let importance = fact["importance"] as? Double else { 
                            print("⚠️ Skipping malformed fact: \(fact)")
                            continue 
                        }
                        
                        let memoryType = mapStringToMemoryType(kindString)
                        
                        print("🔄 ClientAPI: About to store memory:")
                        print("   - Text: \(text)")
                        print("   - Type: \(memoryType.rawValue)")
                        print("   - Importance: \(importance)")
                        
                        await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                            content: text,
                            type: memoryType,
                            source: .conversation,
                            importance: importance
                        )
                        
                        print("📝 Stored \(memoryType.rawValue) memory: \(text.prefix(50))...")
                        storedAny = true
                    }

                    if extractedFacts.isEmpty || !storedAny {
                        let heuristics = self.localHeuristicFacts(from: content)
                        if !heuristics.isEmpty {
                            print("🔄 Heuristic extraction fallback: \(heuristics.count) facts")
                            for h in heuristics {
                                await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                                    content: h.text,
                                    type: mapStringToMemoryType(h.kind),
                                    source: .conversation,
                                    importance: h.importance
                                )
                            }
                        }
                    }
                } else {
                    let statusInfo = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("⚠️ Memory extraction returned invalid payload (status 200). status=\(statusInfo)")
                    let heuristics = self.localHeuristicFacts(from: content)
                    if !heuristics.isEmpty {
                        print("🔄 Heuristic extraction fallback: \(heuristics.count) facts")
                        for h in heuristics {
                            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                                content: h.text,
                                type: mapStringToMemoryType(h.kind),
                                source: .conversation,
                                importance: h.importance
                            )
                        }
                    } else {
                        await fallbackMemoryExtraction(userMessage: content)
                    }
                }
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ Memory extraction HTTP failure: status=\(status)")
                // Fallback to local heuristics
                let heuristics = self.localHeuristicFacts(from: content)
                if !heuristics.isEmpty {
                    print("🔄 Heuristic extraction fallback (HTTP error): \(heuristics.count) facts")
                    for h in heuristics {
                        await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                            content: h.text,
                            type: mapStringToMemoryType(h.kind),
                            source: .conversation,
                            importance: h.importance
                        )
                    }
                } else {
                    await fallbackMemoryExtraction(userMessage: content)
                }
            }
        } catch {
            print("❌ Error extracting memories from server: \(error)")
            // Fallback to simple heuristic extraction
            await fallbackMemoryExtraction(userMessage: content)
        }
    }

    // MARK: - Lightweight heuristic extraction (client-side safety net)
    private func localHeuristicFacts(from content: String) -> [(kind: String, text: String, importance: Double)] {
        var results: [(String, String, Double)] = []
        let lower = content.lowercased()
        // Name
        if let range = lower.range(of: "my name is ") {
            let after = content[range.upperBound...]
            let name = after.split(whereSeparator: { ",[.!?\n]".contains($0) }).first.map(String.init) ?? ""
            if !name.isEmpty {
                results.append(("personal", "User's name is \(name.trimmingCharacters(in: .whitespaces))", 0.9))
            }
        }
        // Nickname
        if let range = lower.range(of: "my nickname is ") {
            let after = content[range.upperBound...]
            let nick = after.split(whereSeparator: { ",[.!?\n]".contains($0) }).first.map(String.init) ?? ""
            if !nick.isEmpty {
                results.append(("personal", "User's nickname is \(nick.trimmingCharacters(in: .whitespaces))", 0.9))
            }
        }
        if lower.contains("call me ") {
            if let r = lower.range(of: "call me ") {
                let after = content[r.upperBound...]
                let nick = after.split(whereSeparator: { ",[.!?\n]".contains($0) }).first.map(String.init) ?? ""
                if !nick.isEmpty {
                    results.append(("personal", "User prefers to be called \(nick.trimmingCharacters(in: .whitespaces))", 0.8))
                }
            }
        }
        // Generic remember-this pattern
        if lower.contains("remember") && lower.contains(" my ") {
            results.append(("instruction", content, 0.7))
        }
        // Location
        if let r = lower.range(of: "i live in ") {
            let after = content[r.upperBound...]
            let loc = after.split(whereSeparator: { ",[.!?\n]".contains($0) }).prefix(3).joined(separator: " ")
            if !loc.isEmpty {
                results.append(("personal", "User lives in \(loc.trimmingCharacters(in: .whitespaces))", 0.8))
            }
        }
        // Preferences
        if let r = lower.range(of: "i like ") {
            let after = content[r.upperBound...]
            let pref = after.split(whereSeparator: { ",[.!?\n]".contains($0) }).prefix(5).joined(separator: " ")
            if !pref.isEmpty { results.append(("preference", "User likes \(pref)", 0.6)) }
        }
        if let r = lower.range(of: "i love ") {
            let after = content[r.upperBound...]
            let pref = after.split(whereSeparator: { ",[.!?\n]".contains($0) }).prefix(5).joined(separator: " ")
            if !pref.isEmpty { results.append(("preference", "User loves \(pref)", 0.6)) }
        }
        return results
    }

    
    private func mapStringToMemoryType(_ kindString: String) -> MemoryType {
        switch kindString.lowercased() {
        case "personal": return .personal
        case "preference": return .preference
        case "professional": return .professional
        case "goal": return .goal
        case "instruction": return .instruction
        case "knowledge": return .knowledge
        case "relationship": return .relationship
        case "event": return .event
        default: return .knowledge
        }
    }
    
    private func fallbackMemoryExtraction(userMessage: String) async {
        // Enhanced fallback when server extraction fails
        let content = userMessage.lowercased()
        
        // Personal information
        if containsPersonalInfo(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .personal,
                source: .conversation,
                importance: 0.8
            )
        }
        
        // Preferences
        if containsPreferences(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .preference,
                source: .conversation,
                importance: 0.7
            )
        }
        
        // Goals and projects
        if containsGoals(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .goal,
                source: .conversation,
                importance: 0.7
            )
        }
        
        // Instructions and requests
        if containsInstructions(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .instruction,
                source: .conversation,
                importance: 0.6
            )
        }
        
        // Professional information
        if containsProfessionalInfo(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .professional,
                source: .conversation,
                importance: 0.7
            )
        }
        
        // Relationships
        if containsRelationships(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .relationship,
                source: .conversation,
                importance: 0.6
            )
        }
        
        // Events and dates
        if containsEvents(content) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .event,
                source: .conversation,
                importance: 0.5
            )
        }
        
        // Important facts and knowledge
        if containsImportantFacts(content) {
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
        let patterns = ["my name is", "i'm ", "i am ", "i live", "my birthday", "my age", "i work at", "i study", 
                       "i was born", "i come from", "my location", "my address"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsPreferences(_ text: String) -> Bool {
        let patterns = ["i like", "i love", "i prefer", "i hate", "i don't like", "my favorite", "i enjoy", 
                       "i dislike", "i'm into", "i'm not into", "i can't stand"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsGoals(_ text: String) -> Bool {
        let patterns = ["project", "goal", "want to", "planning to", "working on", "trying to", "hoping to", "deadline",
                       "target", "aspiration", "aim", "objective", "milestone"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsInstructions(_ text: String) -> Bool {
        let patterns = ["remember", "always", "never", "please", "help me", "remind me", "i need you to", 
                       "can you", "would you", "i want you to", "keep in mind"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsProfessionalInfo(_ text: String) -> Bool {
        let patterns = ["i work", "i'm a", "my job", "i study", "i'm studying", "career", "company", 
                       "university", "college", "profession", "occupation", "employer"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsRelationships(_ text: String) -> Bool {
        let patterns = ["my friend", "my family", "my colleague", "my partner", "my wife", "my husband", 
                       "my child", "my parent", "my sibling", "my coworker", "my team"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsEvents(_ text: String) -> Bool {
        let patterns = ["next week", "tomorrow", "yesterday", "meeting", "appointment", "event", 
                       "vacation", "trip", "conference", "deadline", "schedule", "date"]
        return patterns.contains { text.contains($0) }
    }
    
    private func containsImportantFacts(_ text: String) -> Bool {
        let patterns = ["important", "fact", "information", "details", "know that", "tell you", "should know",
                       "key", "essential", "critical", "significant", "notable"]
        return patterns.contains { text.contains($0) }
    }

    struct GuideReply: Decodable {
        let mode: String?
        let goal_summary: String?
        struct StateAssessment: Decodable { let step_completion: String?; let evidence: [String]?; let confidence: Double? }
        struct UITarget: Decodable { let type: String?; let selector: String? }
        struct NextStep: Decodable { let instruction: String?; let ui_target: UITarget?; let tips: [String]?; let fallback_if_not_visible: String? }
        let state_assessment: StateAssessment?
        let next_step: NextStep?
        let need_new_capture: Bool?
    }

    func callGuide(imageData: Data?, ocrText: String, goal: String, lastInstruction: String, completion: @escaping (Result<GuideReply, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/api/guide")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add API key header for production
        if AppConfig.isCloudDeployed {
            request.setValue(AppConfig.lucaApiKey, forHTTPHeaderField: "X-API-Key")
        }
        var json: [String: Any] = [
            "ocr_text": ocrText,
            "goal": goal,
            "lastInstruction": lastInstruction
        ]
        if let imageData { json["image_base64"] = imageData.base64EncodedString() }
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do { let decoded = try JSONDecoder().decode(GuideReply.self, from: data); completion(.success(decoded)) }
            catch { completion(.failure(error)) }
        }.resume()
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}


