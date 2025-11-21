import Foundation
import FirebaseAuth

struct AnalyzeResponse: Decodable {
    let assistant_text: String
}

// MARK: - Gmail Models
struct GmailStatusResponse: Decodable {
    let connected: Bool
    let email: String?
}

struct GmailAuthURLResponse: Decodable {
    let auth_url: String
}

struct GmailEmailsResponse: Decodable {
    struct Email: Decodable {
        let id: String
        let subject: String?
        let from: String?
        let date: String?
        let snippet: String?
        let text: String?
    }
    let emails: [Email]
}

struct GmailQueryResponse: Decodable {
    let answer: String
    let checked_emails: Int
}

final class ClientAPI {
    static let shared = ClientAPI()
    private init() {}

    var baseURL: URL = AppConfig.serverBaseURL

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
        
        // customPrompt (store actual user question so context/memory have real text)
        if let customPrompt, !customPrompt.isEmpty {
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
                // Store both the user prompt and analysis so context retrieval has the right text
                Task { @MainActor in
                    if let prompt = customPrompt, !prompt.isEmpty {
                        await VectorMemoryManager.shared.storeMessage(content: prompt, role: "user", type: .screenshot)
                    } else {
                        await VectorMemoryManager.shared.storeMessage(content: "Screenshot question", role: "user", type: .screenshot)
                    }
                    await VectorMemoryManager.shared.storeMessage(content: decoded.assistant_text, role: "assistant", type: .analysis)
                }
                
                completion(.success(decoded.assistant_text))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Gmail API
    func gmailStatus(completion: @escaping (Result<GmailStatusResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/api/gmail/status")
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do { completion(.success(try JSONDecoder().decode(GmailStatusResponse.self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    func gmailAuthURL(emailHint: String?, completion: @escaping (Result<URL, Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/gmail/auth"), resolvingAgainstBaseURL: false)!
        if let emailHint, !emailHint.isEmpty { comps.queryItems = [URLQueryItem(name: "email", value: emailHint)] }
        let url = comps.url!
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let decoded = try JSONDecoder().decode(GmailAuthURLResponse.self, from: data)
                if let u = URL(string: decoded.auth_url) { completion(.success(u)) } else {
                    completion(.failure(NSError(domain: "ClientAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Bad auth URL"])))}
            } catch { completion(.failure(error)) }
        }.resume()
    }

    func gmailListEmails(max: Int = 5, completion: @escaping (Result<GmailEmailsResponse, Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/gmail/emails"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "max", value: String(max))]
        let url = comps.url!
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do { completion(.success(try JSONDecoder().decode(GmailEmailsResponse.self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    func gmailQuery(question: String, maxEmails: Int = 10, completion: @escaping (Result<GmailQueryResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/api/gmail/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["question": question, "maxEmails": maxEmails]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do { completion(.success(try JSONDecoder().decode(GmailQueryResponse.self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    func gmailDisconnect(completion: @escaping (Result<Bool, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/api/gmail/disconnect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                completion(.success(obj?["success"] as? Bool == true))
            } catch { completion(.failure(error)) }
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
            
            let context = await VectorMemoryManager.shared.getRelevantMemoriesWithContext(for: message, sessionId: sessionId)

            // Ambient context: location and local time
            var ambient: [String] = []
            if let coord = LocationManager.shared.lastCoordinate {
                ambient.append("Location: lat=\(coord.latitude), lng=\(coord.longitude)")
            }
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d, yyyy h:mm a"
            let timeString = formatter.string(from: now)
            let tz = TimeZone.current
            ambient.append("Local Time: \(timeString) (\(tz.identifier), GMT\(tz.secondsFromGMT()/3600))")
            let ambientBlock = ambient.isEmpty ? "" : "[Ambient Context: \(ambient.joined(separator: "; "))]\n\n"
            
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "message": ambientBlock + message,
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

    // Lightweight chat for inline overlay input: skips heavy context fetch and memory extraction
    func chatLite(message: String, sessionId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Include lightweight capability-aware context header so server can merge with system policy
        let body: [String: Any] = [
            "message": message,
            "sessionId": sessionId ?? "",
            "promptContext": "Relevant Context:\nCapabilities: Screen screenshot+OCR; Gmail if connected; Places search; Session transcripts; Memory."
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
                completion(.success(decoded.assistant_text))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Listen API

    func listenStart(preferredSource: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("/api/listen/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "preferredSource": preferredSource ?? "mic",
            "sessionId": SessionManager.shared.currentSessionId ?? ""
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
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                completion(.success(obj ?? [:]))
            } catch { completion(.failure(error)) }
        }.resume()
    }
    
    private func extractAndStoreMemories(userMessage: String, assistantResponse: String) async {
        // Use the server-side intelligent memory extraction
        await extractMemoriesFromServer(content: "\(userMessage)\n\nAssistant: \(assistantResponse)")
    }
    
    private func extractMemoriesFromServer(content: String) async {
        do {
            let url = URL(string: "\(baseURL)/api/memory/extract")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = [
                "content": content,
                "userId": Auth.auth().currentUser?.uid ?? "unknown",
                "sessionId": SessionManager.shared.currentSessionId
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
                    }
                }
            }
        } catch {
            print("❌ Error extracting memories from server: \(error)")
            // Fallback to simple heuristic extraction
            await fallbackMemoryExtraction(userMessage: content)
        }
    }

    // MARK: - Places API
    struct PlacesSearchResponse: Decodable { struct Item: Decodable { let id: String; let name: String; let rating: Double?; let user_ratings_total: Int?; let address: String?; let open_now: Bool?; let lat: Double?; let lng: Double?; let distance_m: Int?; let google_maps_url: String?; let apple_maps_url: String? }; let query: String; let count: Int; let results: [Item] }

    func placesSearch(query: String, lat: Double, lng: Double, radius: Int = 2000, openNow: Bool = true, completion: @escaping (Result<PlacesSearchResponse, Error>) -> Void) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/places/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "open_now", value: openNow ? "true" : "false")
        ]
        let url = comps.url!
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data else { completion(.failure(NSError(domain: "ClientAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do { completion(.success(try JSONDecoder().decode(PlacesSearchResponse.self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
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
        // Simple fallback when server extraction fails
        if containsPersonalInfo(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .personal,
                source: .conversation,
                importance: 0.8
            )
        }
        
        if containsPreferences(userMessage) {
            await VectorMemoryManager.shared.storeMemoryWithEmbedding(
                content: userMessage,
                type: .preference,
                source: .conversation,
                importance: 0.7
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


