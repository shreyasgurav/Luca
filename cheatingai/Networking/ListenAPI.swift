import Foundation

enum ListenAPI {
    static func start(preferredSource: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        ClientAPI.shared.listenStart(preferredSource: preferredSource, completion: completion)
    }
    static func sendChunk(sessionId: String, audioData: Data, startSec: Int?, endSec: Int?, completion: @escaping (Bool) -> Void) {
        ClientAPI.shared.listenSendChunk(sessionId: sessionId, audioData: audioData, startSec: startSec, endSec: endSec, completion: completion)
    }
    static func stop(sessionId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        ClientAPI.shared.listenStop(sessionId: sessionId, completion: completion)
    }
}


