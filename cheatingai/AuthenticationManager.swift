import Foundation
import FirebaseAuth
import GoogleSignIn
import FirebaseCore

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var isSigningIn = false
    @Published var errorMessage: String?
    
    static let shared = AuthenticationManager()
    
    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                let wasAuthenticated = self?.isAuthenticated ?? false
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                
                // Handle UI transitions
                if wasAuthenticated && !(self?.isAuthenticated ?? false) {
                    // User signed out - hide response overlay (main window stays open)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        ResponseOverlay.shared.hide()
                    }
                } else if !wasAuthenticated && (self?.isAuthenticated ?? false) {
                    // User signed in - show response overlay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ResponseOverlay.shared.show()
                    }
                }
            }
        }
        
        // Handle initial app launch state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.isAuthenticated {
                // Show floating modal if already authenticated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    ResponseOverlay.shared.show()
                }
            }
            // If not authenticated, main window stays open showing sign-in view
        }
    }
    
    func signInWithGoogle() {
        isSigningIn = true
        errorMessage = nil
        
        // Get clientID from Firebase config
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Firebase client ID"
            isSigningIn = false
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Get the presenting window
        guard let window = NSApplication.shared.windows.first else {
            errorMessage = "No window to present from"
            isSigningIn = false
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: window) { [weak self] result, error in
            Task { @MainActor in
                self?.handleGoogleSignInResult(result: result, error: error)
            }
        }
    }
    
    private func handleGoogleSignInResult(result: GIDSignInResult?, error: Error?) {
        if let error = error {
            errorMessage = "Google sign-in error: \(error.localizedDescription)"
            isSigningIn = false
            return
        }
        
        guard let user = result?.user,
              let idToken = user.idToken?.tokenString else {
            errorMessage = "Missing Google ID token"
            isSigningIn = false
            return
        }
        
        let accessToken = user.accessToken.tokenString
        
        // Create Firebase credential with Google tokens
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            Task { @MainActor in
                if let error = error {
                    self?.errorMessage = "Firebase sign-in error: \(error.localizedDescription)"
                } else {
                    print("✅ Successfully signed in user: \(authResult?.user.uid ?? "unknown")")
                }
                self?.isSigningIn = false
            }
        }
    }
    
    func signOut() {
        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
            print("✅ Successfully signed out")
        } catch {
            errorMessage = "Sign out error: \(error.localizedDescription)"
        }
    }
    
    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let error = error {
                print("Could not restore previous sign-in: \(error.localizedDescription)")
            } else if user != nil {
                print("✅ Restored previous Google sign-in")
            }
        }
    }
}
