import Foundation

enum GmailAPI {
    static func status(completion: @escaping (Result<GmailStatusResponse, Error>) -> Void) {
        ClientAPI.shared.gmailStatus(completion: completion)
    }
    static func query(question: String, maxEmails: Int = 10, completion: @escaping (Result<GmailQueryResponse, Error>) -> Void) {
        ClientAPI.shared.gmailQuery(question: question, maxEmails: maxEmails, completion: completion)
    }
}


