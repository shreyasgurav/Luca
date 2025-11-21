import AppKit

/// Custom profile button with Google profile image
class ProfileButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var profileImageView: NSImageView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupProfileButton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupProfileButton()
    }
    
    private func setupProfileButton() {
        self.isBordered = false
        self.title = ""
        self.wantsLayer = true
        self.target = self
        self.action = #selector(showProfileMenu)
        
        // Create circular profile image view
        profileImageView = NSImageView()
        profileImageView?.wantsLayer = true
        profileImageView?.layer?.cornerRadius = 12 // Half of 24px width/height
        profileImageView?.layer?.masksToBounds = true
        profileImageView?.imageScaling = .scaleProportionallyUpOrDown
        
        addSubview(profileImageView!)
        profileImageView?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            profileImageView!.leadingAnchor.constraint(equalTo: leadingAnchor),
            profileImageView!.trailingAnchor.constraint(equalTo: trailingAnchor),
            profileImageView!.topAnchor.constraint(equalTo: topAnchor),
            profileImageView!.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        setupHoverEffect()
        loadGoogleProfileImage()
    }
    
    private func setupHoverEffect() {
        updateTrackingAreas()
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
        // Apply hover effect
        alphaValue = 0.8
        NSCursor.pointingHand.push()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Remove hover effect
        alphaValue = 1.0
        NSCursor.pop()
    }
    
    private func loadGoogleProfileImage() {
        // No user profile with API key auth - show default avatar
        showDefaultAvatar()
    }
    
    private func showDefaultAvatar() {
        // Create a default avatar with "L" for Luca
        let initial = "L"
        
        // Create a circular avatar with gradient background
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw gradient background
        let gradient = NSGradient(colors: [
            NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0), // Blue
            NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)  // Cyan
        ])
        let rect = NSRect(origin: .zero, size: size)
        gradient?.draw(in: rect, angle: 135)
        
        // Draw initial
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedString = NSAttributedString(string: initial, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
        
        image.unlockFocus()
        
        profileImageView?.image = image
    }
    
    @objc private func showProfileMenu() {
        let menu = NSMenu()
        menu.font = NSFont.systemFont(ofSize: 13)
        
        // Navigation items with icons
        let sessionsItem = NSMenuItem(title: "Sessions", action: #selector(selectSessions), keyEquivalent: "")
        sessionsItem.target = self
        sessionsItem.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sessions")
        sessionsItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(sessionsItem)
        
        let memoriesItem = NSMenuItem(title: "Memories", action: #selector(selectMemories), keyEquivalent: "")
        memoriesItem.target = self
        memoriesItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Memories")
        memoriesItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(memoriesItem)
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(selectSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Logout item with icon
        let logoutItem = NSMenuItem(title: "Log Out", action: #selector(logOut), keyEquivalent: "")
        logoutItem.target = self
        logoutItem.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: "Log Out")
        logoutItem.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(logoutItem)
        
        // Style the menu
        menu.appearance = NSAppearance(named: .aqua)
        
        // Align menu with the profile button (right edge)
        let menuSize = menu.size
        let originX = bounds.width - menuSize.width
        let originPoint = NSPoint(x: originX, y: bounds.height + 8)
        menu.popUp(positioning: nil, at: originPoint, in: self)
    }
    
    private func createUserInfoView() -> NSView {
        // Simplified view without user info
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        
        let titleLabel = NSTextField(labelWithString: "Luca")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.frame = NSRect(x: 12, y: 8, width: 200, height: 18)
        containerView.addSubview(titleLabel)
        
        return containerView
    }
    
    private func createDefaultAvatar() -> NSImage {
        let initial = "L"
        let size = NSSize(width: 34, height: 34)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw gradient background
        let gradient = NSGradient(colors: [
            NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
            NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        ])
        let rect = NSRect(origin: .zero, size: size)
        gradient?.draw(in: rect, angle: 135)
        
        // Draw initial
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedString = NSAttributedString(string: initial, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
        
        image.unlockFocus()
        return image
    }
    
    @objc private func selectSessions() {
        NotificationCenter.default.post(name: NSNotification.Name("NavigateToSessions"), object: nil)
    }
    
    @objc private func selectMemories() {
        NotificationCenter.default.post(name: NSNotification.Name("NavigateToMemories"), object: nil)
    }
    
    @objc private func selectSettings() {
        NotificationCenter.default.post(name: NSNotification.Name("NavigateToSettings"), object: nil)
    }
    
    @objc private func logOut() {
        Task { @MainActor in
            APIKeyManager.shared.clearKeys()
            AuthenticationManager.shared.signOut()
        }
    }
}

// MARK: - NSImage Extension for Tinting
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        
        image.unlockFocus()
        return image
    }
}
