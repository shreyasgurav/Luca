import Foundation
import AppKit

enum RoutedAction {
    case screenshot(prompt: String)
    case gmail(question: String)
    case places(query: String)
    case plainChat(message: String)
}

struct IntentRouter {
    static func route(for text: String, lastAssistantMessage: String?) -> RoutedAction {
        let lower = text.lowercased()

        // If assistant just asked for screenshot and user affirmed
        if let last = lastAssistantMessage?.lowercased(), last.contains("screenshot") {
            let affirm = ["yes","ok","okay","sure","do it","go ahead","alright"]
            if affirm.contains(lower) { return .screenshot(prompt: last) }
        }

        if isScreenIntent(lower) && FeatureFlags.screenshotRouteEnabled {
            return .screenshot(prompt: text)
        }
        if isEmailIntent(lower) && FeatureFlags.gmailEnabled {
            return .gmail(question: text)
        }
        if isNearbyIntent(lower) && FeatureFlags.placesEnabled {
            return .places(query: text)
        }
        return .plainChat(message: text)
    }

    private static func isScreenIntent(_ t: String) -> Bool {
        return t.contains("screen") || t.contains("screenshot") || t.contains("what's on") || t.contains("whats on") || t.contains("on my screen") || t.contains("see this") || t.contains("see here") || t.contains("this page") || t.contains("this tab") || t.contains("this slide") || t.contains("look at")
    }

    private static func isEmailIntent(_ t: String) -> Bool {
        let keys = ["email","gmail","inbox","mail","message","check my","in my email","from my email","what did","invite","calendar","meeting","ticket","receipt","otp"]
        return keys.contains { t.contains($0) }
    }

    private static func isNearbyIntent(_ t: String) -> Bool {
        let keys = ["near me","nearby","closest","open now","around me","near"]
        return keys.contains { t.contains($0) }
    }
}


