import SwiftUI

struct DashboardViewRefactored: View {
    @StateObject private var coordinator = DashboardCoordinator()
    @StateObject private var authManager = AuthenticationManager.shared // Still needed for direct sign-in action

    var body: some View {
        Group {
            if coordinator.isAuthenticated {
                if !coordinator.permissionsChecked {
                    // Show loading while checking permissions
                    VStack {
                        ProgressView("Checking permissions...")
                            .font(.headline)
                            .padding()
                    }
                    .frame(minWidth: 600, minHeight: 500)
                    .onAppear {
                        MainWindow.shared.showLoginTitleBar()
                        // Check permissions after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            coordinator.checkPermissionsAndAuthentication()
                        }
                    }
                } else if coordinator.showPermissions {
                    PermissionRequestView()
                        .frame(minWidth: 600, minHeight: 500)
                        .onAppear {
                            MainWindow.shared.showLoginTitleBar()
                        }
                } else {
                VStack(spacing: 0) {
                    // Main content area
                    HStack(spacing: 0) {
                            // Main content area expands to fill entire width
                        mainContentView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 900, minHeight: 600)
                    .onAppear {
                        MainWindow.shared.switchToFullTitleBar()
                        // Only show overlay if we reach this point (all permissions granted)
                        // Small delay to ensure window is fully set up
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            ResponseOverlay.shared.show()
                        }
                    }
                }
            } else {
                // Show only sign-in view without sidebar when not authenticated
                signInView
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    MainWindow.shared.showLoginTitleBar()
                    // Ensure overlay is hidden when showing login
                    ResponseOverlay.shared.hide()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoBack"))) { _ in
            // Handle back button press
            if coordinator.showingSessionDetail {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    coordinator.hideSessionDetail()
                    // Update section title back to "Sessions"
                    MainWindow.shared.updateSectionTitle("Sessions")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSessions"))) { _ in
            if coordinator.selectedTab != .sessions {
                coordinator.selectedTab = .sessions
                // Refresh sessions from Firestore
                coordinator.refreshCurrentSection()
                print("🔄 Refreshed sessions via notification")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMemories"))) { _ in
            if coordinator.selectedTab != .memory {
                coordinator.selectedTab = .memory
                // Refresh memories from Firestore
                coordinator.refreshCurrentSection()
                print("🔄 Refreshed memories via notification")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSettings"))) { _ in
            if coordinator.selectedTab != .settings {
                coordinator.selectedTab = .settings
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LogOut"))) { _ in
            authManager.signOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshContent"))) { _ in
            coordinator.refreshCurrentSection()
        }
        // Avoid rebroadcasting PerformSearch to prevent loops; views handle it directly
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AllPermissionsGranted"))) { _ in
            coordinator.showPermissions = false
            MainWindow.shared.switchToFullTitleBar()
            // Show overlay after permissions are granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ResponseOverlay.shared.show()
            }
        }
        .onChange(of: coordinator.selectedTab) { newTab in
            MainWindow.shared.updateSectionTitle(newTab.rawValue)
            
            // Refresh data when switching to sessions or memory tabs
            if newTab == .sessions || newTab == .memory {
                coordinator.refreshCurrentSection()
            }
        }
        .onAppear {
            if coordinator.isAuthenticated {
                // Check permissions on authenticated state
                coordinator.checkPermissionsAndAuthentication()
            }
        }
        .background(Color.white)
    }
    
    // MARK: - Main Content
    
    private var mainContentView: some View {
        Group {
            switch coordinator.selectedTab {
            case .memory:
                MemoryView()
            case .sessions:
                SessionsView()
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 5)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: coordinator.selectedTab)
    }
    
    // MARK: - Sign In View
    
    private var signInView: some View {
        APIKeyInputView()
    }
}

#Preview {
    DashboardViewRefactored()
}
