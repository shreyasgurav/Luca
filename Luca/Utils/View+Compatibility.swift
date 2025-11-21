import SwiftUI

// Compatibility helpers for older macOS deployment targets
extension View {
    @ViewBuilder
    func listRowSeparatorHiddenCompat() -> some View {
        if #available(macOS 13.0, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
    }
}


