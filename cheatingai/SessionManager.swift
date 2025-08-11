import Foundation

final class SessionManager {
    static let shared = SessionManager()
    private init() {}

    private(set) var currentSessionId: String? = UUID().uuidString
    func newSession() { currentSessionId = UUID().uuidString }
}


