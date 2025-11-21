import Foundation

enum FeatureFlags {
    // Toggle major capabilities; defaults are safe and match current behavior
    static let screenshotRouteEnabled: Bool = true
    static let ocrEnabled: Bool = true
    static let streamingSTTEnabled: Bool = false

    static let placesEnabled: Bool = true
    static let memoryExtractEnabled: Bool = true
}


