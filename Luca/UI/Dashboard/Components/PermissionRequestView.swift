import SwiftUI
import AVFoundation
import Speech
import CoreGraphics
import ScreenCaptureKit

struct PermissionRequestView: View {
    @State private var screenRecordingGranted = false
    @State private var microphoneGranted = false
    @State private var speechRecognitionGranted = false
    
    private var allPermissionsGranted: Bool {
        screenRecordingGranted && microphoneGranted && speechRecognitionGranted
    }
    
    var body: some View {
        VStack(spacing: 40) {
            // Header
            VStack(spacing: 16) {
                Image("LucaLogoBlack")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                
                Text("Grant Permissions")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Luca needs a few permissions to work properly")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Permission List - Single Row
            HStack(spacing: 12) {
                PermissionRow(
                    icon: "rectangle.and.pencil.and.ellipsis",
                    title: "Screen Recording",
                    description: "Capture system audio and screenshots",
                    isGranted: $screenRecordingGranted,
                    action: requestScreenRecordingPermission
                )
                
                PermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "Listen to audio when system audio is unavailable",
                    isGranted: $microphoneGranted,
                    action: requestMicrophonePermission
                )
                
                PermissionRow(
                    icon: "waveform",
                    title: "Speech Recognition",
                    description: "Transcribe audio for real-time notes",
                    isGranted: $speechRecognitionGranted,
                    action: requestSpeechRecognitionPermission
                )
            }
            
            // Continue Button (only shown when all permissions are granted)
            if allPermissionsGranted {
                Button(action: proceedToMainApp) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Continue to Luca")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(allPermissionsGranted ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: allPermissionsGranted)
            }
        }
        .padding(40)
        .frame(maxWidth: 500)
        .onAppear {
            checkAllPermissions()
        }
    }
    
    private func checkAllPermissions() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            checkScreenRecordingPermission()
            checkMicrophonePermission()
            checkSpeechRecognitionPermission()
        }
    }
    
    private func checkScreenRecordingPermission() {
        if #available(macOS 12.3, *) {
            // Use ScreenCaptureKit for modern macOS
            Task {
                do {
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    await MainActor.run {
                        self.screenRecordingGranted = true
                        print("🎬 Screen recording permission: GRANTED")
                    }
                } catch {
                    await MainActor.run {
                        self.screenRecordingGranted = false
                        print("🎬 Screen recording permission: DENIED - \(error)")
                    }
                }
            }
        } else if #available(macOS 10.15, *) {
            // Fallback to legacy method
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            print("🎬 Screen recording permission (legacy): \(screenRecordingGranted ? "GRANTED" : "DENIED")")
        } else {
            screenRecordingGranted = true // Assume granted on older versions
            print("🎬 Screen recording permission (old macOS): ASSUMED GRANTED")
        }
    }
    
    private func requestScreenRecordingPermission() {
        print("🎬 Requesting screen recording permission...")
        
        // Check if permission was previously denied
        if #available(macOS 12.3, *) {
            Task {
                do {
                    // Try to get available content first to check current status
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    await MainActor.run {
                        self.screenRecordingGranted = true
                        print("🎬 Screen recording permission: GRANTED")
                        self.checkAllPermissionsAndProceed()
                    }
                } catch {
                    await MainActor.run {
                        self.screenRecordingGranted = false
                        print("🎬 Screen recording permission: DENIED - \(error)")
                        
                        // If permission was denied, show instructions to user
                        self.showScreenRecordingInstructions()
                    }
                }
            }
        } else {
            // For older macOS versions, use CGDisplayStream
            let displayStream = CGDisplayStream(
                dispatchQueueDisplay: CGMainDisplayID(),
                outputWidth: 1,
                outputHeight: 1,
                pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                properties: nil,
                queue: DispatchQueue.main
            ) { _, _, _, _ in
                // Empty callback
            }
            
            displayStream?.start()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                displayStream?.stop()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkScreenRecordingPermission()
                    if !self.screenRecordingGranted {
                        self.showScreenRecordingInstructions()
                    }
                    self.checkAllPermissionsAndProceed()
                }
            }
        }
    }
    
    private func showScreenRecordingInstructions() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        To enable screen recording:
        
        1. Go to System Preferences → Security & Privacy → Privacy
        2. Select "Screen Recording" from the left sidebar
        3. Check the box next to "Luca" to grant permission
        4. Restart Luca after granting permission
        
        If Luca is not listed, try running the app once more and check again.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Open System Preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case .alertSecondButtonReturn:
            // Try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.requestScreenRecordingPermission()
            }
        default:
            break
        }
    }
    
    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    microphoneGranted = granted
                }
            }
        default:
            microphoneGranted = false
        }
    }
    
    private func requestMicrophonePermission() {
        print("🎤 Requesting microphone permission...")
        
        // Always try to request permission, regardless of current status
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                print("🎤 Microphone permission result: \(granted)")
                self.microphoneGranted = granted
                
                if !granted {
                    self.showMicrophoneInstructions()
                }
                
                self.checkAllPermissionsAndProceed()
            }
        }
    }
    
    private func showMicrophoneInstructions() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = """
        To enable microphone access:
        
        1. Go to System Preferences → Security & Privacy → Privacy
        2. Select "Microphone" from the left sidebar
        3. Check the box next to "Luca" to grant permission
        4. Restart Luca after granting permission
        
        If Luca is not listed, try running the app once more and check again.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Open System Preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        case .alertSecondButtonReturn:
            // Try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.requestMicrophonePermission()
            }
        default:
            break
        }
    }
    
    private func checkSpeechRecognitionPermission() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionGranted = true
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    speechRecognitionGranted = (status == .authorized)
                }
            }
        default:
            speechRecognitionGranted = false
        }
    }
    
    private func requestSpeechRecognitionPermission() {
        print("🗣️ Requesting speech recognition permission...")
        
        // Always try to request permission, regardless of current status
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                print("🗣️ Speech recognition permission result: \(status.rawValue)")
                self.speechRecognitionGranted = (status == .authorized)
                
                if status != .authorized {
                    self.showSpeechRecognitionInstructions()
                }
                
                self.checkAllPermissionsAndProceed()
            }
        }
    }
    
    private func showSpeechRecognitionInstructions() {
        let alert = NSAlert()
        alert.messageText = "Speech Recognition Permission Required"
        alert.informativeText = """
        To enable speech recognition:
        
        1. Go to System Preferences → Security & Privacy → Privacy
        2. Select "Speech Recognition" from the left sidebar
        3. Check the box next to "Luca" to grant permission
        4. Restart Luca after granting permission
        
        If Luca is not listed, try running the app once more and check again.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Open System Preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        case .alertSecondButtonReturn:
            // Try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.requestSpeechRecognitionPermission()
            }
        default:
            break
        }
    }
    
    
    private func checkAllPermissionsAndProceed() {
        // Check all permissions and proceed if all are granted
        checkAllPermissions()
        if allPermissionsGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.proceedToMainApp()
            }
        }
    }
    
    
    private func proceedToMainApp() {
        // Verify all permissions are actually granted before proceeding
        if allPermissionsGranted {
            NotificationCenter.default.post(name: NSNotification.Name("AllPermissionsGranted"), object: nil)
            print("✅ All permissions verified - proceeding to main app")
        } else {
            print("⚠️ Cannot proceed - not all permissions are granted")
            // Re-check permissions to update UI
            checkAllPermissions()
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isGranted: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 20)
            
            // Content
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                if !isGranted {
                    Text("Click to request")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .italic()
                }
            }
            
            // Status
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(isGranted ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .cursor(.pointingHand)
    }
}

// Extension for cursor support
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { _ in
            cursor.push()
        }
    }
}

#Preview {
    PermissionRequestView()
}
