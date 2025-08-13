import SwiftUI

struct MainAppView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        DashboardView()
            .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }
}

#Preview {
    MainAppView()
}
