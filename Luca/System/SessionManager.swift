import Foundation

final class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var currentSessionId: String?
    
    private init() {
        // Initialize with a new session ID
        currentSessionId = UUID().uuidString
        // Post notification for other components to sync
        NotificationCenter.default.post(name: .sessionDidChange, object: currentSessionId)
    }
    
    func startNewSession() {
        currentSessionId = UUID().uuidString
        // Post notification for other components to sync
        NotificationCenter.default.post(name: .sessionDidChange, object: currentSessionId)
    }
    
    func getCurrentSessionId() -> String {
        if let sessionId = currentSessionId {
            return sessionId
        } else {
            let newSessionId = UUID().uuidString
            currentSessionId = newSessionId
            // Post notification for other components to sync
            NotificationCenter.default.post(name: .sessionDidChange, object: newSessionId)
            return newSessionId
        }
    }
}

extension Notification.Name {
    static let sessionDidChange = Notification.Name("sessionDidChange")
}
