import Foundation

// Updated ChatMessage struct with segments support
struct ChatMessage: Identifiable {
    // stable id used by SwiftUI ForEach / scrollTo
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    let hasScreenshot: Bool
    // NEW: parsed segments (filled when assistant appends)
    var segments: [MessageSegment]?
    
    init(content: String, isUser: Bool, hasScreenshot: Bool = false, segments: [MessageSegment]? = nil) {
        self.content = content
        self.isUser = isUser
        self.hasScreenshot = hasScreenshot
        self.timestamp = Date()
        self.segments = segments
    }
}
