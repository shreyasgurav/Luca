import Foundation

final class ConversationManager {
    static let shared = ConversationManager()
    private init() {}

    struct Turn: Codable {
        enum Role: String, Codable { case system, user, assistant }
        let role: Role
        let content: String
        let timestamp: Date
    }

    private let maxTokenBudget: Int = 7000 // approx for thread context
    private let maxRecentTurns: Int = 12
    private var turns: [Turn] = []
    private var summary: String? = nil

    func clear() {
        turns.removeAll()
        summary = nil
    }

    func addUser(_ text: String) {
        append(role: .user, content: text)
    }

    func addAssistant(_ text: String) {
        append(role: .assistant, content: text)
    }

    func addSystem(_ text: String) {
        append(role: .system, content: text)
    }

    private func append(role: Turn.Role, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        turns.append(Turn(role: role, content: trimmed, timestamp: Date()))
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        // Estimate tokens of full thread
        let total = (summary?.count ?? 0) + turns.reduce(0) { $0 + $1.content.count }
        let tokenEstimate = total / 4
        guard tokenEstimate > maxTokenBudget else { return }

        // Summarize older half of the turns
        guard turns.count > 6 else { return }
        let half = turns.count / 2
        let older = turns.prefix(half)
        let merged = older.map { "\($0.role.rawValue.capitalized): \($0.content)" }.joined(separator: "\n")
        let capped = String(merged.prefix(2000))
        if let existing = summary {
            summary = existing + "\n" + capped
        } else {
            summary = capped
        }
        turns = Array(turns.suffix(from: half))
    }

    func recentThreadContext() -> String {
        var blocks: [String] = []
        if let summary, !summary.isEmpty {
            blocks.append("Summary so far:\n" + summary)
        }
        let recent = Array(turns.suffix(maxRecentTurns))
        if !recent.isEmpty {
            let formatted = recent.map { turn in
                let tag: String
                switch turn.role {
                case .user: tag = "User"
                case .assistant: tag = "Assistant"
                case .system: tag = "System"
                }
                return "\(tag): \(turn.content)"
            }.joined(separator: "\n")
            blocks.append("Recent conversation:\n" + formatted)
        }
        return blocks.joined(separator: "\n\n")
    }
}


