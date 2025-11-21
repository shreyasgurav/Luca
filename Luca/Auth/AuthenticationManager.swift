import Foundation
import Combine

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    static let shared = AuthenticationManager()
    private let apiKeyManager = APIKeyManager.shared
    
    private init() {
        // Check API keys on init
        checkAPIKeys()
        
        // Observe API key changes
        apiKeyManager.$hasValidKeys
            .sink { [weak self] hasKeys in
                Task { @MainActor in
                    self?.isAuthenticated = hasKeys
                    if hasKeys {
                        // Load sessions when keys are validated
                        SessionTranscriptStore.shared.refreshSessions()
                        NotificationCenter.default.post(name: NSNotification.Name("AuthenticationStateChanged"), object: nil)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Handle initial app launch state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainWindow.shared.show()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func checkAPIKeys() {
        isAuthenticated = apiKeyManager.validateKeys()
    }
    
    func signOut() {
        apiKeyManager.clearKeys()
        isAuthenticated = false
        print("✅ API keys cleared")
        NotificationCenter.default.post(name: NSNotification.Name("AuthenticationStateChanged"), object: nil)
    }
}
