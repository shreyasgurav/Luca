import SwiftUI
import GoogleSignInSwift

struct SignInView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        VStack(spacing: 24) {
            // App Branding
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("CheatingAI")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Sign in to continue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Sign-in content
            VStack(spacing: 16) {
                if authManager.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(height: 44)
                } else {
                    GoogleSignInButton(action: authManager.signInWithGoogle)
                        .frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .frame(width: 300, height: 400)
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}

#Preview {
    SignInView()
}
