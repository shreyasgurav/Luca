import Foundation

enum AppEnvironment: String {
    case development
    case production
}

struct AppConfig {
    static let environment: AppEnvironment = .development
    static var serverBaseURL: URL {
        switch environment {
        case .development:
            return URL(string: "http://localhost:3000")!
        case .production:
            // Replace with your production endpoint
            return URL(string: "https://api.nova.app")!
        }
    }
}


