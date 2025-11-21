import Foundation
import SwiftUI

// -----------------------------
// ConversationStore (single source of truth)
// -----------------------------
final class ConversationStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    
    // Append user message (ensure UI update on main thread)
    func appendUser(_ text: String) {
        DispatchQueue.main.async {
            self.messages.append(ChatMessage(content: text, isUser: true))
        }
    }
    
    // Append assistant message
    func appendAssistant(_ text: String, hasScreenshot: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            let segments = MessageParser.parseSegments(from: text)
            DispatchQueue.main.async {
                self.messages.append(ChatMessage(content: text, isUser: false, hasScreenshot: hasScreenshot, segments: segments))
            }
        }
    }
    
    // Clear conversation
    func clear() {
        DispatchQueue.main.async {
            self.messages.removeAll()
        }
    }
    
    // Build a compact context string from recent messages (safe for token limits)
    func buildContext(limitMessages: Int = 6, perMessageLimit: Int = 800) -> String {
        let recent = messages.suffix(limitMessages)
        guard !recent.isEmpty else { return "" }
        let lines = recent.map { m -> String in
            let trimmed = m.content.prefix(perMessageLimit)
            let role = m.isUser ? "User" : "Assistant"
            return "\(role): \(trimmed)"
        }
        return lines.joined(separator: "\n")
    }
    
    // Helper: last assistant message (optional)
    func lastAssistantMessage() -> String? {
        return messages.last(where: { !$0.isUser })?.content
    }
}
