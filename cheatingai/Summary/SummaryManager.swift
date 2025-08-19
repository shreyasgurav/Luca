import Foundation

final class SummaryManager: NSObject {
	static let shared = SummaryManager()
	private override init() {}

	struct ChatMessage: Codable {
		let role: String
		let content: String
	}

	struct ChatRequest: Codable {
		let model: String
		let messages: [ChatMessage]
		let temperature: Double
	}

	struct ChatResponse: Codable {
		struct Choice: Codable {
			struct Message: Codable { let content: String }
			let message: Message
		}
		let choices: [Choice]
	}

	func generateSummary(from transcript: String) async throws -> String {
		let apiKey = Self.resolveAPIKey()
		guard !apiKey.isEmpty else {
			throw NSError(domain: "SummaryManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not set. Set OPENAI_API_KEY env or in UserDefaults."])
		}

		let prep = Self.preprocess(transcript)
		let prompt = Self.buildPrompt(for: prep.text, lowSignal: prep.lowSignal)

		var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
		request.httpMethod = "POST"
		request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let body = ChatRequest(
			model: "gpt-4o-mini",
			messages: [
				ChatMessage(role: "system", content: "You are an expert meeting and media summarizer. Be concise, precise, and actionable. Avoid repeating filler."),
				ChatMessage(role: "user", content: prompt)
			],
			temperature: 0.2
		)
		request.httpBody = try JSONEncoder().encode(body)

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
			let err = String(data: data, encoding: .utf8) ?? "Unknown error"
			throw NSError(domain: "SummaryManager", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: err])
		}

		let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
		guard let text = parsed.choices.first?.message.content, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw NSError(domain: "SummaryManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty summary from model"])
		}
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func resolveAPIKey() -> String {
		if let key = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"), !key.isEmpty { return key }
		if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty { return key }
		return ""
	}

	private static func preprocess(_ transcript: String) -> (text: String, lowSignal: Bool) {
		let lines = transcript.components(separatedBy: .newlines)
		var seen = Set<String>()
		var cleaned: [String] = []
		var fillerCount = 0

		for raw in lines {
			let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			if line.isEmpty { continue }

			let lower = line.lowercased()
			// Drop known guidance/silence lines
			if lower.contains("[no system audio detected]") { continue }
			if lower.contains("to capture youtube/zoom") { continue }
			if lower.contains("blackhole") { continue }
			if lower.contains("[no speech detected") { continue }

			// Treat obvious filler as low-signal
			if isLikelyFiller(lower) {
				fillerCount += 1
				// keep at most one instance of a filler line
				if seen.insert(lower).inserted { cleaned.append(line) }
				continue
			}

			// Deduplicate exact repeats (case-insensitive)
			if seen.insert(lower).inserted {
				cleaned.append(line)
			}
		}

		let joined = cleaned.joined(separator: "\n")
		let contentChars = joined.count
		let lowSignal = contentChars < 80 || (cleaned.count <= 2 && fillerCount > 0)
		return (joined, lowSignal)
	}

	private static func isLikelyFiller(_ lower: String) -> Bool {
		// Common repeated non-informational patterns
		if lower == "thank you for watching." || lower == "thank you for watching" { return true }
		if lower.contains("boom") { return true }
		if lower.contains("bzzz") { return true }
		// Emoji-only or symbols-only (no letters/digits from any language)
		let letters = lower.unicodeScalars.contains { CharacterSet.letters.contains($0) }
		let digits = lower.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
		return !(letters || digits) && lower.count <= 24
	}

	private static func buildPrompt(for transcript: String, lowSignal: Bool) -> String {
		if lowSignal {
			return """
			You will summarize a very low-signal session consisting mostly of filler (e.g., repeated thanks, sound effects, or short exclamations).
			Return ONE line only, no sections, in this exact format:
			Low-signal session: <concise one-sentence description; no bullets, no extra commentary>.
			
			Transcript (deduplicated):
			\(transcript)
			"""
		}

		return """
		Summarize the following session transcript for a user. Output in this format only:
		
		- Summary: 1-3 sentences focusing on substance (skip pleasantries).
		- Highlights: up to 5 bullets with concrete facts/quotes only.
		- Action Items: numbered list; include owner if implied; omit if none.
		- Follow-up Questions: up to 3 concise questions; omit if none.
		- Tags: 3-6 comma-separated keywords.
		
		Strictly avoid repeating filler (e.g., repeated thanks, emojis, sound effects). Preserve non-English content succinctly.
		Do not fabricate details not present in the transcript.
		
		Transcript (deduplicated):
		\(transcript)
		"""
	}
}


