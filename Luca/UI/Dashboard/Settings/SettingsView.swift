import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Show Luca while sharing screen")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Toggle("", isOn: Binding(
                    get: { AppConfig.isVisibleInScreenCapture },
                    set: { newValue in
                        AppConfig.isVisibleInScreenCapture = newValue
                        // Update existing windows
                        ResponseOverlay.shared.panel?.sharingType = newValue ? .readOnly : .none
                        MainWindow.shared.updateSharingType()
                        // Update multi-window overlay system
                        WindowOrchestrator.shared.updateSharingType()
                        // Update tooltip windows
                        TooltipWindowManager.shared.updateSharingType()
                        // Hide/show app icon in dock
                        updateDockVisibility(hidden: !newValue)
                    }
                ))
                .toggleStyle(SwitchToggleStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.top, 100)
            
            HStack {
                Text("Auto Launch")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Toggle("", isOn: Binding(
                    get: { AppConfig.isAutoLaunchEnabled },
                    set: { newValue in
                        AppConfig.isAutoLaunchEnabled = newValue
                        print("Auto launch toggled: \(newValue)")
                    }
                ))
                .toggleStyle(SwitchToggleStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.top, 16)
            
            Spacer()
            
            // Quit Luca Button - Bottom Center
            HStack {
                Spacer()
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Text("Quit Luca")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHovering in
                    // Subtle hover effect
                }
                Spacer()
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 300)
    }
    
    // MARK: - Dock Visibility Functions
    
    private func updateDockVisibility(hidden: Bool) {
        DispatchQueue.main.async {
            if hidden {
                // Hide from dock but keep windows functional
                NSApp.setActivationPolicy(.accessory)
                // Immediately restore window management without affecting dock
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Ensure main window stays open and functional
                    for window in NSApp.windows {
                        if window.isMainWindow || window.title.contains("Luca") {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                    // Re-activate the app to keep it functional
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                // Show in dock with full functionality
                NSApp.setActivationPolicy(.regular)
            }
            print("Dock visibility updated: \(hidden ? "hidden" : "visible")")
        }
    }
    
}

#Preview {
    SettingsView()
}
