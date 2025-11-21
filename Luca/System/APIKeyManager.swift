import Foundation
import Security
import Combine

@MainActor
class APIKeyManager: ObservableObject {
    static let shared = APIKeyManager()
    
    @Published var openAIKey: String = ""
    @Published var deepgramKey: String = ""
    @Published var hasValidKeys: Bool = false
    
    private let openAIKeychainKey = "com.luca.openai.apikey"
    private let deepgramKeychainKey = "com.luca.deepgram.apikey"
    
    private init() {
        loadKeys()
        checkAndValidateKeys()
    }
    
    // MARK: - Key Storage (Secure Keychain)
    
    func saveOpenAIKey(_ key: String) {
        openAIKey = key
        saveToKeychain(key: key, for: openAIKeychainKey)
        checkAndValidateKeys()
    }
    
    func saveDeepgramKey(_ key: String) {
        deepgramKey = key
        saveToKeychain(key: key, for: deepgramKeychainKey)
        checkAndValidateKeys()
    }
    
    func clearKeys() {
        openAIKey = ""
        deepgramKey = ""
        deleteFromKeychain(for: openAIKeychainKey)
        deleteFromKeychain(for: deepgramKeychainKey)
        hasValidKeys = false
    }
    
    // MARK: - Key Loading
    
    private func loadKeys() {
        openAIKey = loadFromKeychain(for: openAIKeychainKey) ?? ""
        deepgramKey = loadFromKeychain(for: deepgramKeychainKey) ?? ""
    }
    
    // MARK: - Validation
    
    private func checkAndValidateKeys() {
        // Basic validation: keys should not be empty and have minimum length
        let openAIValid = !openAIKey.isEmpty && openAIKey.hasPrefix("sk-") && openAIKey.count > 20
        let deepgramValid = !deepgramKey.isEmpty && deepgramKey.count > 20
        
        hasValidKeys = openAIValid && deepgramValid
        
        if hasValidKeys {
            // Update DeepgramConfig to use the stored key
            updateDeepgramConfig()
        }
    }
    
    func validateKeys() -> Bool {
        checkAndValidateKeys()
        return hasValidKeys
    }
    
    private func updateDeepgramConfig() {
        // This will be used by DeepgramSTT
        UserDefaults.standard.set(deepgramKey, forKey: "DeepgramAPIKey")
    }
    
    // MARK: - Keychain Helpers
    
    private func saveToKeychain(key: String, for identifier: String) {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadFromKeychain(for identifier: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    private func deleteFromKeychain(for identifier: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - User ID (for local-only operations)
    
    nonisolated var localUserId: String {
        // Generate a stable local user ID based on machine
        if let existing = UserDefaults.standard.string(forKey: "LocalUserId") {
            return existing
        }
        
        let newUserId = UUID().uuidString
        UserDefaults.standard.set(newUserId, forKey: "LocalUserId")
        return newUserId
    }
}

