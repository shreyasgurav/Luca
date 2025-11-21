import SwiftUI
import Combine
import AVFoundation
import Speech

// MARK: - Dashboard Tab Enum
enum DashboardTab: String, CaseIterable {
    case memory = "Memory"
    case sessions = "Sessions"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .sessions: return "waveform"
        case .settings: return "gearshape"
        }
    }
    
    var logoImage: some View {
        Group {
            switch self {
            case .memory:
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .frame(width: 16, height: 16)
            case .sessions:
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .frame(width: 16, height: 16)
            case .settings:
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Dashboard Coordinator
@MainActor
class DashboardCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedTab: DashboardTab = .sessions
    @Published var showingSessionDetail = false
    @Published var selectedSession: ListenSession?
    @Published var showingMemoryDetail = false
    @Published var selectedMemory: VectorMemory?
    @Published var refreshTrigger = UUID()

    // MARK: - State Management
    @Published var isAuthenticated = false
    @Published var showPermissions = false
    @Published var permissionsChecked = false

    // MARK: - Dependencies
    private let authManager = AuthenticationManager.shared
    private let memoryManager = VectorMemoryManager.shared
    private let transcriptStore = SessionTranscriptStore.shared

    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
        // Don't check permissions immediately - wait for authentication state to be determined
        // Permissions will be checked when the view appears
    }

    private func setupBindings() {
        authManager.$isAuthenticated
            .assign(to: &$isAuthenticated)
    }

    func checkPermissionsAndAuthentication() {
        // Check permissions
        let screenCaptureStatus = CGPreflightScreenCaptureAccess()
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        print("🔍 Permission check results:")
        print("   Screen Recording: \(screenCaptureStatus)")
        print("   Microphone: \(microphoneStatus == .authorized)")
        print("   Speech Recognition: \(speechStatus == .authorized)")

        if screenCaptureStatus && microphoneStatus == .authorized && speechStatus == .authorized {
            showPermissions = false
            permissionsChecked = true
            print("✅ All permissions granted - proceeding to main app")
        } else {
            showPermissions = true
            permissionsChecked = true // Set to true so we don't get stuck in loading
            print("⚠️ Some permissions missing - showing permission request")
        }
    }

    func requestPermissions() {
        // Permissions are handled by the PermissionRequestView
        checkPermissionsAndAuthentication() // Re-check after requesting
    }

    func refreshCurrentSection() {
        switch selectedTab {
        case .sessions:
            transcriptStore.refreshSessions()
            print("🔄 Coordinator: Refreshed sessions")
        case .memory:
            // MemoryView handles its own refresh via onReceive, but we can trigger a load here if needed
            refreshTrigger = UUID() // Trigger a refresh in MemoryView
            print("🔄 Coordinator: Triggered memory refresh")
        case .settings:
            // Settings usually don't need refresh
            break
        }
    }

    func performSearch(query: String) {
        // This will be handled by individual views, but the coordinator can pass the query
        NotificationCenter.default.post(name: NSNotification.Name("PerformSearch"), object: query)
        print("🔍 Coordinator: Performed search with query: \(query)")
    }

    func clearSearch() {
        NotificationCenter.default.post(name: NSNotification.Name("ClearSearch"), object: nil)
        print("🔍 Coordinator: Cleared search")
    }

    // MARK: - Navigation Actions
    func showSessionDetail(session: ListenSession) {
        selectedSession = session
        showingSessionDetail = true
    }

    func hideSessionDetail() {
        selectedSession = nil
        showingSessionDetail = false
    }

    func showMemoryDetail(memory: VectorMemory) {
        selectedMemory = memory
        showingMemoryDetail = true
    }

    func hideMemoryDetail() {
        selectedMemory = nil
        showingMemoryDetail = false
    }
}
