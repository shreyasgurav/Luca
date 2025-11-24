import SwiftUI
import AppKit

class MainWindow {
    static let shared = MainWindow()
    private var window: NSWindow?
    private var sectionTitleLabel: NSTextField?
    private var searchField: NSSearchField?
    private var searchButton: NSButton?
    private var refreshButton: NSButton?
    private var backButton: NSButton?
    private var profileButton: NSButton?
    
    private init() {
        // Listen for authentication state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authenticationStateChanged),
            name: NSNotification.Name("AuthenticationStateChanged"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func authenticationStateChanged() {
        DispatchQueue.main.async {
            let isAuthenticated = AuthenticationManager.shared.isAuthenticated
            
            print("🔍 Authentication state changed - isAuthenticated: \(isAuthenticated)")
            
            if isAuthenticated {
                // User just authenticated, switch to full title bar
                print("✅ Switching to full title bar")
                self.switchToFullTitleBar()
            } else {
                // User logged out, switch to login title bar
                print("✅ Switching to login title bar")
                self.showLoginTitleBar()
            }
        }
    }
    
    func show() {
        if window == nil {
            createWindow()
        }
        
        // Ensure window is ready before showing
        guard let window = window else { return }
        
        // Force window to be properly sized and centered
        let targetSize = NSSize(width: 1100, height: 750)
        window.setContentSize(targetSize)
        
        // Small delay to ensure window is fully set up before centering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            // Ensure window is properly centered on the main screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
                let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
                let newOrigin = CGPoint(x: x, y: y)
                print("🪟 MainWindow: Centering at \(newOrigin) on screen frame \(screenFrame), window frame \(windowFrame)")
                window.setFrameOrigin(newOrigin)
            } else {
                print("🪟 MainWindow: Using fallback center() method")
                window.center()
            }
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Bring to front and ensure it's visible
        window.orderFrontRegardless()
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func showCentered() {
        show() // This already centers the window
    }

    /// Bring the existing main window to the front on its current Space and switch to it
    func focusExistingSpace() {
        if window == nil { createWindow() }
        guard let window = window else { return }

        // Ensure it's not pinned to all spaces so macOS can switch to the window's Space
        window.collectionBehavior.remove(.canJoinAllSpaces)

        // Activate app and make this window key/front; macOS will switch to the Space containing it
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    
    func updateSharingType() {
        if AppConfig.isVisibleInScreenCapture {
            window?.sharingType = .readOnly
        } else {
            window?.sharingType = .none
        }
    }
    
    private func createWindow() {
        let mainAppView = MainAppView()
        let hostingController = NSHostingController(rootView: mainAppView)
        
        // Force light appearance on hosting controller
        hostingController.view.appearance = NSAppearance(named: .aqua)
        
        // Create window with initial size, position will be set by center() call
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Keep the default title bar but make it transparent for custom content
        self.window?.titlebarAppearsTransparent = true
        
        // Force light appearance regardless of system theme
        self.window?.appearance = NSAppearance(named: .aqua)
        
        // Set window background to pure white
        self.window?.backgroundColor = NSColor.white
        
        // Keep window title empty since we use custom section title
        self.window?.title = ""
        
        // Add sidebar toggle button to the title bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Check if user is authenticated to determine title bar content
            let isAuthenticated = AuthenticationManager.shared.isAuthenticated
            
            if isAuthenticated {
            self.addSidebarToggleToTitleBar()
                // Initialize with Sessions section (which should show search bar)
                self.updateTitleBarForSection("Sessions")
            } else {
                // Show login title bar (just title, no buttons)
                self.addLoginTitleBar()
            }
        }
        self.window?.contentViewController = hostingController
        self.window?.isReleasedWhenClosed = false
        
        // Set minimum size
        self.window?.minSize = NSSize(width: 400, height: 500)
        
        // Set screen capture visibility based on user preference
        if AppConfig.isVisibleInScreenCapture {
            self.window?.sharingType = .readOnly
        } else {
            self.window?.sharingType = .none
        }
    }
    
    private func updateWindowTitle() {
        // Intentionally keep title simple as requested
        window?.title = "" // Hide window title since we have custom section title
    }
    
    @MainActor
    func updateTitle(_ newTitle: String) {
        // Don't update window title - we use custom section title instead
        // window?.title = newTitle
        
        // Update the section title label and trigger title bar logic
        self.sectionTitleLabel?.stringValue = newTitle
        self.updateTitleBarForSection(newTitle)
    }
    
    private func addSidebarToggleToTitleBar() {
        guard let window = window else { return }
        
        // Prevent duplicate UI injection
        guard self.backButton == nil, self.profileButton == nil, self.searchField == nil else {
            print("⚠️ Title bar buttons already exist, skipping re-add.")
            return
        }
        
        // Find the title bar view
        guard let titleBarView = window.standardWindowButton(.closeButton)?.superview else { return }
        
        // Create the back button with hover effect
        let backButton = HoverButton()
        backButton.title = ""
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.imagePosition = .imageOnly
        backButton.isBordered = false
        backButton.target = self
        backButton.action = #selector(goBack)
        
        // Store reference
        self.backButton = backButton
        
        // Position the back button to the right of the window controls
        titleBarView.addSubview(backButton)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Position it after the green (maximize) button with some spacing
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: window.standardWindowButton(.zoomButton)!.trailingAnchor, constant: 15),
            backButton.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor, constant: 3),
            backButton.widthAnchor.constraint(equalToConstant: 20),
            backButton.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Create the profile button on the right side
        let profileButton = ProfileButton()
        
        // Store reference
        self.profileButton = profileButton

        titleBarView.addSubview(profileButton)
        profileButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            profileButton.trailingAnchor.constraint(equalTo: titleBarView.trailingAnchor, constant: -7),
            profileButton.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor, constant: 3),
            profileButton.widthAnchor.constraint(equalToConstant: 24),
            profileButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        
        // Add section title label centered
        let sectionTitleLabel = NSTextField()
        sectionTitleLabel.stringValue = "Luca"
        sectionTitleLabel.isEditable = false
        sectionTitleLabel.isBezeled = false
        sectionTitleLabel.drawsBackground = false
        sectionTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        // Use fixed dark color instead of adaptive labelColor
        sectionTitleLabel.textColor = NSColor(white: 0.0, alpha: 1.0)
        sectionTitleLabel.alignment = .center
        
        titleBarView.addSubview(sectionTitleLabel)
        sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sectionTitleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor),
            sectionTitleLabel.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor, constant: 3),
            sectionTitleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        
        // Store reference to update title later
        self.sectionTitleLabel = sectionTitleLabel
        
        // Create search field (initially hidden)
        let searchField = NSSearchField()
        searchField.placeholderString = "Search..."
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.isHidden = true
        
        // Force light appearance for search field
        searchField.appearance = NSAppearance(named: .aqua)
        
        // Remove only the blue focus ring, keep original border
        searchField.focusRingType = .none
        
        // Disable the built-in clear button
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = false
        
        // Hide the built-in clear button by removing the search menu
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.cancelButtonCell = nil
            // Set fixed text color for search field
            cell.textColor = NSColor(white: 0.0, alpha: 1.0)
        }
        
        // Add subtle darker border with rounded corners - use fixed light colors
        searchField.wantsLayer = true
        searchField.layer?.backgroundColor = NSColor(white: 1.0, alpha: 1.0).cgColor
        searchField.layer?.borderColor = NSColor(white: 0.75, alpha: 1.0).cgColor
        searchField.layer?.borderWidth = 0.5
        searchField.layer?.cornerRadius = 12.0
        
        titleBarView.addSubview(searchField)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchField.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor),
            searchField.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor, constant: 3),
            searchField.widthAnchor.constraint(equalToConstant: 300)
        ])
        
        // Store reference
        self.searchField = searchField
        
        // Create search button as a separate view (not inside search field)
        let searchButton = NSButton()
        searchButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Search")
        searchButton.imagePosition = .imageOnly
        searchButton.isBordered = false
        searchButton.target = self
        searchButton.action = #selector(searchButtonClicked)
        searchButton.isEnabled = true
        
        // Style the button with background - use fixed light color
        searchButton.wantsLayer = true
        searchButton.appearance = NSAppearance(named: .aqua)
        DispatchQueue.main.async {
            searchButton.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1.0).cgColor
            searchButton.layer?.cornerRadius = 9
            searchButton.layer?.masksToBounds = true
        }
        
        // Add the button back inside the search field but properly positioned
        searchField.addSubview(searchButton)
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchButton.trailingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: -8),
            searchButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 18),
            searchButton.heightAnchor.constraint(equalToConstant: 18)
        ])
        
        // Store reference
        self.searchButton = searchButton
        
        // Create refresh button (initially hidden)
        let refreshButton = NSButton()
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.imagePosition = .imageOnly
        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)
        refreshButton.isHidden = true
        
        titleBarView.addSubview(refreshButton)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            refreshButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            refreshButton.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor, constant: 3),
            refreshButton.widthAnchor.constraint(equalToConstant: 20),
            refreshButton.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Store reference
        self.refreshButton = refreshButton
    }
    
    @objc private func showProfileMenu() {
        // Post a notification that the profile menu should be shown
        NotificationCenter.default.post(name: NSNotification.Name("ShowProfileMenu"), object: nil)
    }
    
    @objc private func goBack() {
        // Post a notification that the back action should be triggered
        NotificationCenter.default.post(name: NSNotification.Name("GoBack"), object: nil)
    }
    
    @objc private func refreshButtonClicked() {
        // Post a notification that the refresh action should be triggered
        NotificationCenter.default.post(name: NSNotification.Name("RefreshContent"), object: nil)
    }
    
    @objc private func searchButtonClicked() {
        print("🔍 Search button clicked!")
        if let searchField = self.searchField {
            if searchField.stringValue.isEmpty {
                // If empty, focus the field instead of sending an empty search
                window?.makeFirstResponder(searchField)
            } else {
                // Clear button clicked - clear search
                print("🔍 Clearing search field: '\(searchField.stringValue)'")
                searchField.stringValue = ""
                updateSearchButtonState()
                NotificationCenter.default.post(name: NSNotification.Name("ClearSearch"), object: nil)
                print("🔍 Search field cleared!")
            }
        } else {
            print("⚠️ Search field is nil!")
        }
    }

    
    @MainActor
    func updateSectionTitle(_ title: String) {
        self.sectionTitleLabel?.stringValue = title
        self.updateTitleBarForSection(title)
    }
    
    @MainActor
    func updateTitleBarForTab(_ tab: String) {
        self.sectionTitleLabel?.stringValue = tab
        self.updateTitleBarForSection(tab)
    }
    
    @MainActor
    private func updateTitleBarForSection(_ section: String) {
        let isAuthenticated = AuthenticationManager.shared.isAuthenticated
        // Centralized visibility logic based on section and auth state
        let showSearchBar = isAuthenticated && (section == "Sessions" || section == "Memory")
        let showBackButton = (section == "Session Details")  // Show back only for Session Details
        let showProfileButton = isAuthenticated && section != "Login"  // Hide profile when logged out
        
        sectionTitleLabel?.isHidden = showSearchBar
        sectionTitleLabel?.stringValue = section  // Update the title text
        searchField?.isHidden = !showSearchBar
        searchButton?.isHidden = !showSearchBar
        refreshButton?.isHidden = !showSearchBar
        backButton?.isHidden = !showBackButton
        profileButton?.isHidden = !showProfileButton
        
        if showSearchBar {
            searchField?.placeholderString = "Search \(section)..."
        }
    }
    
    // Centralized title bar state management
    @MainActor
    private func rebuildTitleBarForState(isAuthenticated: Bool, currentSection: String) {
        if isAuthenticated {
            // Full title bar with all elements
            if backButton == nil || profileButton == nil || searchField == nil {
                addSidebarToggleToTitleBar()
            }
            updateTitleBarForSection(currentSection)
        } else {
            // Login state - no title bar
            showLoginTitleBar()
        }
    }
    
    private func addLoginTitleBar() {
        guard let window = window else { return }
        
        // Find the title bar view
        guard let titleBarView = window.standardWindowButton(.closeButton)?.superview else { return }
        
        // Add section title label centered
        let sectionTitleLabel = NSTextField()
        sectionTitleLabel.stringValue = "Luca"
        sectionTitleLabel.isEditable = false
        sectionTitleLabel.isBezeled = false
        sectionTitleLabel.drawsBackground = false
        sectionTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        // Use fixed dark color instead of adaptive labelColor
        sectionTitleLabel.textColor = NSColor(white: 0.0, alpha: 1.0)
        sectionTitleLabel.alignment = .center
        
        titleBarView.addSubview(sectionTitleLabel)
        sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sectionTitleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor),
            sectionTitleLabel.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor, constant: 3),
            sectionTitleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        
        // Store reference to update title later
        self.sectionTitleLabel = sectionTitleLabel
    }
    
    func showLoginTitleBar() {
        DispatchQueue.main.async {
            print("🔍 showLoginTitleBar called")
            
            // Remove all existing title bar elements completely AND reset references
            self.searchField?.removeFromSuperview()
            self.searchField = nil
            
            self.searchButton?.removeFromSuperview()
            self.searchButton = nil
            
            self.refreshButton?.removeFromSuperview()
            self.refreshButton = nil
            
            self.backButton?.removeFromSuperview()
            self.backButton = nil
            
            self.profileButton?.removeFromSuperview()
            self.profileButton = nil
            
            self.sectionTitleLabel?.removeFromSuperview()
            self.sectionTitleLabel = nil
            
            print("🔍 All title bar elements removed and references reset")
            
            // Resize window for login (smaller size)
            self.resizeWindowForLogin()
            
            // Add clean login title bar with just "Luca"
            self.addLoginTitleBar()
            
            print("✅ Login page - no title bar")
        }
    }
    
    private func resizeWindowForLogin() {
        guard let window = window else { return }
        
        // Set smaller size for login
        let loginSize = NSSize(width: 400, height: 500)
        window.setContentSize(loginSize)
        
        // Center the window
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - loginSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - loginSize.height) / 2
            let newOrigin = CGPoint(x: x, y: y)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    func switchToFullTitleBar() {
        DispatchQueue.main.async {
            print("🔍 switchToFullTitleBar called")
            
            // Clean up any existing login title bar elements
            self.sectionTitleLabel?.removeFromSuperview()
            self.sectionTitleLabel = nil
            
            // Resize window back to full size
            self.resizeWindowForMainApp()
            
            // Add full title bar with all elements (will skip if already exists)
            self.addSidebarToggleToTitleBar()
            self.updateTitleBarForSection("Sessions")
            
            print("✅ Switched to full title bar")
        }
    }
    
    private func resizeWindowForMainApp() {
        guard let window = window else { return }
        
        // Set full size for main app
        let fullSize = NSSize(width: 1100, height: 750)
        window.setContentSize(fullSize)
        
        // Center the window
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - fullSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - fullSize.height) / 2
            let newOrigin = CGPoint(x: x, y: y)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    @objc private func searchFieldChanged() {
        // Update button state based on search field content
        updateSearchButtonState()
        
        guard let searchText = searchField?.stringValue else { return }
        // Send only when text changes; no global rebroadcast loops
        NotificationCenter.default.post(name: NSNotification.Name("PerformSearch"), object: searchText)
    }
    
    private func updateSearchButtonState() {
        guard let searchButton = self.searchButton, let searchField = self.searchField else { return }
        
        if searchField.stringValue.isEmpty {
            // Show search arrow when field is empty
            searchButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Search")
        } else {
            // Show clear X when field has text
            searchButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        }
    }
}

// Custom button class with hover effect
class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupHoverEffect()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupHoverEffect()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHoverEffect()
    }
    
    private func setupHoverEffect() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Add tracking area
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Use fixed light gray color instead of adaptive controlBackgroundColor
        layer?.backgroundColor = NSColor(white: 0.9, alpha: 1.0).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

