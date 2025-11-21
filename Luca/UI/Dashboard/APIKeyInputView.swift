import SwiftUI

struct APIKeyInputView: View {
    @StateObject private var apiKeyManager = APIKeyManager.shared
    @State private var openAIKey: String = ""
    @State private var deepgramKey: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    
    enum Field {
        case openAI, deepgram
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Content container
            VStack(spacing: 48) {
                // Logo and title
                VStack(spacing: 16) {
                    Image("LucaLogoBlack")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                    
                    VStack(spacing: 8) {
                        Text("Welcome to Luca")
                            .font(.system(size: 32, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                        
                        Text("Enter your API keys to continue")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Input fields
                VStack(spacing: 20) {
                    // OpenAI field
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OpenAI API Key")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        SecureField("sk-...", text: $openAIKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(focusedField == .openAI ? Color.gray.opacity(0.6) : Color.gray.opacity(0.25), lineWidth: 1)
                            )
                            .focused($focusedField, equals: .openAI)
                            .onChange(of: openAIKey) { newValue in
                                if !newValue.contains("•") && newValue.hasPrefix("sk-") && newValue.count > 20 {
                                    apiKeyManager.saveOpenAIKey(newValue)
                                }
                            }
                    }
                    
                    // Deepgram field
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Deepgram API Key")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your API key", text: $deepgramKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(focusedField == .deepgram ? Color.gray.opacity(0.6) : Color.gray.opacity(0.25), lineWidth: 1)
                            )
                            .focused($focusedField, equals: .deepgram)
                            .onChange(of: deepgramKey) { newValue in
                                if !newValue.contains("•") && newValue.count > 20 {
                                    apiKeyManager.saveDeepgramKey(newValue)
                                }
                            }
                    }
                }
                .frame(width: 420)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(width: 420)
                }
                
                // Continue button
                Button(action: {
                    saveKeys()
                }) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.9)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        
                        Text(isSaving ? "Saving..." : "Continue")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(width: 420)
                    .frame(height: 44)
                    .foregroundColor(.white)
                    .background(canSave ? Color.accentColor : Color.gray.opacity(0.3))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
                
                // Help links
                HStack(spacing: 12) {
                    Link("Get OpenAI Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.system(size: 13))
                    
                    Text("•")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Link("Get Deepgram Key", destination: URL(string: "https://console.deepgram.com/signup")!)
                        .font(.system(size: 13))
                }
                .foregroundColor(.accentColor)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            MainWindow.shared.showLoginTitleBar()
            // Load existing keys (masked for display)
            if !apiKeyManager.openAIKey.isEmpty {
                openAIKey = maskAPIKey(apiKeyManager.openAIKey)
            }
            if !apiKeyManager.deepgramKey.isEmpty {
                deepgramKey = maskAPIKey(apiKeyManager.deepgramKey)
            }
        }
    }
    
    private var canSave: Bool {
        // Basic validation: keys should not be empty
        let openAIValid = !openAIKey.isEmpty && openAIKey.hasPrefix("sk-") && openAIKey.count > 20
        let deepgramValid = !deepgramKey.isEmpty && deepgramKey.count > 20
        
        return openAIValid && deepgramValid
    }
    
    private func saveKeys() {
        isSaving = true
        errorMessage = nil
        
        // Check if keys are masked (already saved) or new
        let actualOpenAIKey: String
        let actualDeepgramKey: String
        
        if openAIKey.hasPrefix("sk-") && openAIKey.count > 30 {
            // Likely a real key (not masked)
            actualOpenAIKey = openAIKey
        } else if openAIKey.contains("•") {
            // Masked key, use existing
            actualOpenAIKey = apiKeyManager.openAIKey
        } else {
            actualOpenAIKey = openAIKey
        }
        
        if deepgramKey.count > 20 && !deepgramKey.contains("•") {
            actualDeepgramKey = deepgramKey
        } else if deepgramKey.contains("•") {
            // Masked key, use existing
            actualDeepgramKey = apiKeyManager.deepgramKey
        } else {
            actualDeepgramKey = deepgramKey
        }
        
        // Validate keys before saving
        guard actualOpenAIKey.hasPrefix("sk-") && actualOpenAIKey.count > 20 else {
            errorMessage = "Invalid OpenAI API key format"
            isSaving = false
            return
        }
        
        guard actualDeepgramKey.count > 20 else {
            errorMessage = "Invalid Deepgram API key format"
            isSaving = false
            return
        }
        
        // Save keys
        apiKeyManager.saveOpenAIKey(actualOpenAIKey)
        apiKeyManager.saveDeepgramKey(actualDeepgramKey)
        
        // Validate
        if apiKeyManager.validateKeys() {
            isSaving = false
            // AuthenticationManager will automatically update isAuthenticated
        } else {
            errorMessage = "Failed to validate API keys"
            isSaving = false
        }
    }
    
    private func maskAPIKey(_ key: String) -> String {
        guard key.count > 10 else { return "••••••••" }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        let masked = String(repeating: "•", count: key.count - 8)
        return prefix + masked + suffix
    }
}

