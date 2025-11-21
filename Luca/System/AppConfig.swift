import Foundation
import ServiceManagement
import CoreServices

enum AppEnvironment: String {
    case development
    case production
}

struct AppConfig {
    // 🌟 Change this to .production when you deploy to cloud
    static let environment: AppEnvironment = .production
    
    // 🆕 User preference for screen capture visibility
    static var isVisibleInScreenCapture: Bool {
        get {
            UserDefaults.standard.bool(forKey: "isVisibleInScreenCapture")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isVisibleInScreenCapture")
        }
    }
    
    // 🚀 User preference for auto launch
    static var isAutoLaunchEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "isAutoLaunchEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isAutoLaunchEnabled")
            // Update Login Items when setting changes
            updateLoginItems(enabled: newValue)
        }
    }
    
    // MARK: - Auto Launch Implementation
    
    /// Syncs the current auto-launch setting with macOS Login Items
    static func syncAutoLaunchWithLoginItems() {
        let currentSetting = isAutoLaunchEnabled
        let isInLoginItems = isAppInLoginItems()
        
        // If settings don't match Login Items, update Login Items to match settings
        if currentSetting != isInLoginItems {
            updateLoginItems(enabled: currentSetting)
        }
    }
    
    /// Checks if the app is currently in Login Items
    private static func isAppInLoginItems() -> Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }

        let appPath = Bundle.main.bundlePath
        guard let listRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue() else {
            return false
        }
        guard let snapshot = LSSharedFileListCopySnapshot(listRef, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return false
        }
        for item in snapshot {
            if let urlRef = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() {
                let url = urlRef as URL
                if url.path == appPath { return true }
            }
        }
        return false
    }
    
    private static func updateLoginItems(enabled: Bool) {
        if #available(macOS 13.0, *) {
            if enabled {
                do { try SMAppService.mainApp.register(); print("✅ Added Luca to Login Items") } catch { print("❌ Failed to add Luca to Login Items: \(error)") }
            } else {
                do { try SMAppService.mainApp.unregister(); print("✅ Removed Luca from Login Items") } catch { print("❌ Failed to remove Luca from Login Items: \(error)") }
            }
            return
        }

        let appPath = Bundle.main.bundlePath
        guard let listRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue() else {
            print("❌ Failed to create login items list")
            return
        }
        if enabled {
            let urlRef = URL(fileURLWithPath: appPath) as CFURL
            let _ = LSSharedFileListInsertItemURL(listRef, kLSSharedFileListItemLast.takeUnretainedValue(), nil, nil, urlRef, nil, nil)
            print("✅ Added Luca to Login Items")
        } else {
            if let items = LSSharedFileListCopySnapshot(listRef, nil)?.takeRetainedValue() as? [LSSharedFileListItem] {
                for item in items {
                    if let urlRef = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() {
                        let url = urlRef as URL
                        if url.path == appPath {
                            LSSharedFileListItemRemove(listRef, item)
                            print("✅ Removed Luca from Login Items")
                            break
                        }
                    }
                }
            }
        }
    }
    
    // 🔧 Easy switching between local and cloud
    static var serverBaseURL: URL {
        switch environment {
        case .development:
            // Local development server
            return URL(string: "http://localhost:3000")!
        case .production:
            // Cloud API endpoint - Using original working URL
            return URL(string: "https://lucaserver1.vercel.app")!
        }
    }
    
    // 📱 Helper computed properties
    static var isLocalDevelopment: Bool {
        return environment == .development
    }
    
    static var isCloudDeployed: Bool {
        return environment == .production
    }
    
    // 🔐 API Key for Vercel deployment
    static var lucaApiKey: String {
        return "7c8e3f59-2e2b-4d1c-9f01-5a2a9f8d7c31"
    }
}


