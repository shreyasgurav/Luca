import Foundation
import FirebaseAuth
import GoogleSignIn
import FirebaseCore

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    static let shared = AuthenticationManager()
    
    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        
        // Get clientID from Firebase config
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Firebase client ID"
            isLoading = false
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Get the presenting window
        guard let window = NSApplication.shared.windows.first else {
            errorMessage = "No window to present from"
            isLoading = false
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
            isLoading = false
            return
        }
        
        guard let user = result?.user,
              let idToken = user.idToken?.tokenString else {
            errorMessage = "Missing Google ID token"
            isLoading = false
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
                self?.isLoading = false
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
