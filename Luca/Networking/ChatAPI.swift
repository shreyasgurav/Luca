import Foundation

enum ChatAPI {
    static func send(message: String, sessionId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        ClientAPI.shared.chat(message: message, sessionId: sessionId, completion: completion)
    }
}


