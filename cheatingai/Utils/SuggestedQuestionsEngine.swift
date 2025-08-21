import Foundation
import Combine
import NaturalLanguage

@MainActor
final class SuggestedQuestionsEngine: ObservableObject {
    static let shared = SuggestedQuestionsEngine()

    struct Suggestion: Identifiable, Hashable {
        enum Source { case verbatim, topic, llm }
        let id = UUID()
        let text: String
        let source: Source
        let score: Double
    }

    // Public suggestions for UI
    @Published private(set) var suggestions: [Suggestion] = []

    // Config
    private let maxSuggestions = 3
    private let minWordsForVerbatim = 3
    private let minCharsForTopic = 4
    private let rollingWindowMaxChars = 1200
    private let minWindowCharsForLLM = 80
    private let llmCooldownSec: TimeInterval = 30

    // Internal
    private var rollingBuffer: [String] = []
    private var seenNormalized = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var lastLLMCall: Date? = nil
    private var pendingLLMCall: UUID? = nil

    // Blacklist for generic nouns
    private let genericBlacklist: Set<String> = [
        "company","product","thing","someone","somebody","people","team","time","meeting","person","issue","stuff","work"
    ]

    private let questionWords: Set<String> = [
        "who","what","why","how","when","where","which","can","should","is","are","do","does","did","could","would","will","may"
    ]

    private init() {
        SessionTranscriptStore.shared.$lastFinalUtterance
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] utterance in
                Task { @MainActor in
                    await self?.ingestFinalUtterance(utterance)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Ingest
    private func ingestFinalUtterance(_ utterance: String) async {
        appendToBuffer(utterance)

        // 1) Try to extract verbatim questions (highest priority)
        let verbatim = extractVerbatimQuestions(from: utterance)
        var candidates: [Suggestion] = []
        for v in verbatim {
            let norm = normalize(v)
            if self.isAcceptableVerbatim(v) && !isDuplicate(norm) {
                candidates.append(Suggestion(text: v, source: .verbatim, score: 1.0))
                markSeen(norm)
            }
        }

        // 2) If not enough, extract scored topics from rolling buffer
        if candidates.count < maxSuggestions {
            let topics = extractCandidateTopics(from: rollingBuffer.joined(separator: " "))
            for t in topics {
                let q = generateContextualQuestion(for: t.phrase, context: t.context)
                let norm = normalize(q)
                if !isDuplicate(norm) {
                    candidates.append(Suggestion(text: q, source: .topic, score: t.score))
                    markSeen(norm)
                }
                if candidates.count >= maxSuggestions { break }
            }
        }

        // 3) If still not enough, optionally top-up with LLM (throttled)
        if candidates.count < maxSuggestions {
            let now = Date()
            if shouldCallLLM(now: now) {
                lastLLMCall = now
                await callLLMForSuggestions(window: rollingBuffer.joined(separator: " "))
                // LLM handler will merge results asynchronously
            }
        }

        // 4) Merge into public suggestions (keep newest highest)
        if !candidates.isEmpty {
            // prefer verbatim first
            candidates.sort { ($0.score, $0.source == .verbatim ? 1 : 0) > ($1.score, $1.source == .verbatim ? 1 : 0) }
            let merged = (candidates + suggestions).uniqued() // keep existing uniqueness
            suggestions = Array(merged.prefix(maxSuggestions))
        }
    }

    // MARK: - Helpers

    private func appendToBuffer(_ ut: String) {
        rollingBuffer.append(ut)
        // trim by chars
        while rollingBuffer.joined(separator: " ").count > rollingWindowMaxChars {
            if !rollingBuffer.isEmpty { rollingBuffer.removeFirst() }
        }
    }

    private func isAcceptableVerbatim(_ s: String) -> Bool {
        let words = s.split(separator: " ")
        guard words.count >= minWordsForVerbatim else { return false }
        // simple question-word presence or a terminal '?'
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return true }
        let firstWord = words.first.map { $0.lowercased() } ?? ""
        if questionWords.contains(firstWord) { return true }
        // also consider sentences where question word appears early
        if words.prefix(4).contains(where: { questionWords.contains($0.lowercased()) }) { return true }
        return false
    }

    private func extractVerbatimQuestions(from s: String) -> [String] {
        // Split into sentences; keep ones that look like questions.
        let sentences = splitIntoSentences(s)
        return sentences.filter { isAcceptableVerbatim($0) }
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var results: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            results.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        }
        return results
    }

    // Candidate topic extraction returns phrases with a score and optional short context
    private func extractCandidateTopics(from text: String) -> [(phrase: String, score: Double, context: String)] {
        guard text.count >= minCharsForTopic else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text

        var candidates: [String: (count: Int, isProper: Bool, occurrences: [Range<String.Index>])] = [:]

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard let tag = tag else { return true }
            if tag == .noun {
                let word = String(text[range]).lowercased()
                // ignore generic short words
                if word.count < 3 { return true }
                if genericBlacklist.contains(word) { return true }
                // accumulate
                if var cur = candidates[word] {
                    cur.count += 1
                    cur.occurrences.append(range)
                    candidates[word] = cur
                } else {
                    candidates[word] = (1, false, [range])
                }
            }
            return true
        }

        // Also extract named entity multi-word names (persons, organizations, places)
        var namedEntities: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if let tag = tag, tag != .other {
                let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if name.count > 3 && !genericBlacklist.contains(name) {
                    namedEntities.append(name)
                }
            }
            return true
        }

        // Build scored list: named entities get high base score
        var scored: [(phrase: String, score: Double, context: String)] = []

        for (word, meta) in candidates {
            let freq = Double(meta.count)
            var score = freq
            if meta.isProper { score += 1.5 } // proper noun bonus
            // length bonus
            score += Double(max(0, word.count - 5)) * 0.05
            // context snippet: nearest 40 chars around first occurrence
            let firstRange = meta.occurrences.first!
            let contextStart = text.index(firstRange.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            let contextEnd = text.index(firstRange.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
            let context = String(text[contextStart..<contextEnd])
            scored.append((phrase: word, score: score, context: context))
        }

        for ne in namedEntities {
            // if duplicate with candidates, boost that entry
            if let idx = scored.firstIndex(where: { $0.phrase == ne }) {
                scored[idx].score += 2.0
            } else {
                scored.append((phrase: ne, score: 3.0, context: ne))
            }
        }

        // prefer multi-word phrases: merge adjacent nouns where possible (heuristic)
        scored.sort { $0.score > $1.score }
        // filter and return top few
        return scored
            .filter { $0.phrase.count >= minCharsForTopic }
            .prefix(5)
            .map { $0 }
    }

    private func generateContextualQuestion(for phrase: String, context: String) -> String {
        // Prefer richer templates, not "What is <phrase>?"
        let p = phrase.capitalized
        // If phrase contains more than 1 word, ask "How does <p> affect ...?"
        if p.split(separator: " ").count >= 2 {
            return "How does \(p) affect our work or project?"
        } else {
            // single-word phrase: produce a slightly richer question if possible
            return "Can someone explain \(p) and its implications for our team?"
        }
    }

    // Normalization + dedupe
    private func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func isDuplicate(_ norm: String) -> Bool {
        // fuzzy check: exact or similar
        if seenNormalized.contains(norm) { return true }
        for seen in seenNormalized {
            let sim = similarity(between: seen, and: norm)
            if sim > 0.85 { return true } // too similar
        }
        return false
    }

    private func markSeen(_ norm: String) {
        seenNormalized.insert(norm)
    }

    // Simple similarity using normalized Levenshtein ratio
    private func similarity(between a: String, and b: String) -> Double {
        let ld = Double(levenshtein(a, b))
        let maxLen = Double(max(a.count, b.count))
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - (ld / maxLen)
    }

    // MARK: - LLM fallback (throttled)
    private func shouldCallLLM(now: Date) -> Bool {
        guard (lastLLMCall == nil) || (now.timeIntervalSince(lastLLMCall!) > llmCooldownSec) else { return false }
        // only call if we have some buffer
        return rollingBuffer.joined(separator: " ").count >= minWindowCharsForLLM
    }

    private func callLLMForSuggestions(window: String) async {
        // Small safety: send only the last X chars
        let payload = String(window.suffix(800))
        pendingLLMCall = UUID()
        let callId = pendingLLMCall!

        // Use ClientAPI.listenSuggest to call server route; handle success merging
        ClientAPI.shared.listenSuggest(window: payload) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.pendingLLMCall == callId else { return } // stale canceled
                switch result {
                case .success(let resp):
                    var added: [Suggestion] = []
                    for v in resp.verbatim {
                        let norm = self.normalize(v)
                        if !self.isDuplicate(norm) && v.split(separator: " ").count >= self.minWordsForVerbatim {
                            added.append(Suggestion(text: v, source: .llm, score: 0.9))
                            self.markSeen(norm)
                        }
                    }
                    for t in resp.topics {
                        let q = t.hasSuffix("?") ? t : (t + "?")
                        let norm = self.normalize(q)
                        if !self.isDuplicate(norm) {
                            added.append(Suggestion(text: q, source: .llm, score: 0.6))
                            self.markSeen(norm)
                        }
                    }

                    if !added.isEmpty {
                        let merged = (added + self.suggestions).uniqued()
                        self.suggestions = Array(merged.prefix(self.maxSuggestions))
                    }
                case .failure(let err):
                    // log and ignore
                    print("LLM suggest error: \(err.localizedDescription)")
                }
                self.pendingLLMCall = nil
            }
        }
    }

    // MARK: - Utilities: levenshtein
    private func levenshtein(_ s: String, _ t: String) -> Int {
        let a = Array(s)
        let b = Array(t)
        let n = a.count, m = b.count
        var d = Array(repeating: Array(repeating: 0, count: m+1), count: n+1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let cost = (a[i-1] == b[j-1]) ? 0 : 1
                d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
            }
        }
        return d[n][m]
    }
}

// Small helpers
fileprivate extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var s = Set<Element>()
        return filter { s.insert($0).inserted }
    }
}
