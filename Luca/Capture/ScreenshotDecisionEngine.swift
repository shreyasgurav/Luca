import Foundation

enum ScreenshotDecision {
    case forceCapture   // user explicitly asks to look at screen
    case probeCapture   // likely useful — do a cheap probe first
    case noCapture      // do not capture
}

/// Small, tweakable heuristic engine. Keep this local and fast — it's just
/// to avoid unnecessary screen captures. You can also send ambiguous cases
/// to the LLM later for a judgement if you want.
struct ScreenshotDecisionEngine {
    static func decide(for message: String, lastAssistant: String? = nil) -> ScreenshotDecision {
        let t = message.lowercased()
        print("🔍 ScreenshotDecisionEngine: Analyzing message: '\(message)'")
        
        // explicit opt-out
        if t.contains("don't check") || t.contains("do not check") || t.contains("dont check") || t.contains("no screen") || t.contains("no screenshot") {
            print("🔍 ScreenshotDecisionEngine: Explicit opt-out detected -> noCapture")
            return .noCapture
        }
        
        // explicit ask to show the screen
        let forceKeys = [
            "what's on screen", "whats on screen", "what's on my screen", "whats on my screen",
            "show me", "check my screen", "check screen", "look at screen", "screenshot", 
            "capture screen", "screen shot", "see my screen", "see screen", "whats this", 
            "what's this", "what is this", "see this", "look at this", "check this", 
            "view screen", "show screen", "display screen", "what's happening", "whats happening",
            "on my screen", "on screen", "screen content", "current screen", "my screen"
        ]
        if forceKeys.contains(where: { t.contains($0) }) { 
            print("🔍 ScreenshotDecisionEngine: Force capture keyword matched -> forceCapture")
            return .forceCapture 
        }
        
        // Additional pattern matching for screen-related queries with more flexibility
        if (t.contains("what") || t.contains("whats")) && t.contains("screen") {
            print("🔍 ScreenshotDecisionEngine: What+screen pattern matched -> forceCapture")
            return .forceCapture
        }
        
        // strong signals that a visible error / stack/ code is relevant
        let probeStrong = [
            "error", "exception", "stack trace", "traceback", "crash", "segmentation fault", 
            "panic", "compile error", "syntax error", "not working", "fails", "failing", 
            "bug", "fix this", "how to fix", "solve this", "debug", "why is", "what does this",
            "what should i", "which option", "what to", "how do i", "help me", "opened", 
            "select here", "choose", "pick", "what next", "now what", "what do", "guide me"
        ]
        if probeStrong.contains(where: { t.contains($0) }) { 
            print("🔍 ScreenshotDecisionEngine: Probe capture keyword matched -> probeCapture")
            return .probeCapture 
        }

        // If user is short and ambiguous but uses words like "solve" or "explain this", probe.
        if t.contains("solve") || t.contains("explain this") || t.contains("help with this") {
            print("🔍 ScreenshotDecisionEngine: Ambiguous help keyword matched -> probeCapture")
            return .probeCapture
        }

        // default: do not capture
        print("🔍 ScreenshotDecisionEngine: No patterns matched -> noCapture")
        return .noCapture
    }
}
