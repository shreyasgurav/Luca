import Foundation
import AVFoundation
import CoreAudio
import ScreenCaptureKit
import AppKit
import CoreGraphics
import Combine
import os.log

@MainActor
final class AudioCaptureManager: NSObject, ObservableObject {
    static let shared = AudioCaptureManager()

    // MARK: - Published Properties for UI
    @Published var isListening = false
    @Published var liveTranscript = ""
    @Published var connectionStatus = "Ready"
    
    // MARK: - Debug Properties
    @Published var isAudioFlowing = false
    @Published var audioLevelDebug: Float = 0.0
    @Published var lastAudioTimestamp: Date?
    private let logger = Logger(subsystem: "com.luca.app", category: "AudioCapture")

    // MARK: - Audio Capture Properties
    private var screenCaptureSession: SCStream?
    private var audioEngine = AVAudioEngine()
    
    // ScreenCaptureKit → Deepgram conversion
    private var scInputFormat: AVAudioFormat?
    private let dgTargetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!
    private var scToDgConverter: AVAudioConverter?
    private var micConverter: AVAudioConverter?
    
    // AVCaptureSession-based mic capture (works better with Bluetooth headsets)
    private var micCaptureSession: AVCaptureSession?
    private var micDeviceInput: AVCaptureDeviceInput?
    private var micDataOutput: AVCaptureAudioDataOutput?
    private var preferredMicDeviceUniqueID: String?
    struct MicDeviceInfo: Identifiable, Equatable {
        let id: String
        let uid: String
        let name: String
        let isDefault: Bool
    }
    @Published var availableMics: [MicDeviceInfo] = []
    
    // MARK: - STT Integration (Multi-source)
    private let multiSTT = MultiSourceSTTManager()
    private var cancellables = Set<AnyCancellable>()
    
    // Audio processing
    private var accumulatingPCM = Data()            // system buffer
    private var micAccumulatingPCM = Data()         // microphone buffer
    private var accumulatedSamples: Int = 0
    private let targetSampleRate: Double = 16_000
    private let chunkSizeBytes = DeepgramConfig.chunkSizeBytes // 50ms chunks for real-time
    private var samplesPerChunk: Int { chunkSizeBytes / 2 } // 16-bit samples
    
    // Session management
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var isRunning = false
    private var lastNonSilenceAt: Date = Date()
    private var lastVoiceActivity: Date = Date()
    private var isStopping: Bool = false
    
    // VAD Configuration
    private let voiceThreshold: Float = 0.01
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupDeepgramIntegration()
        // Removed device monitoring since we always use built-in microphone
    }
    
    // MARK: - Public Interface
    
    /// Start listening with Deepgram STT
    func startListening(sessionId: String? = nil, onStarted: @escaping (Bool) -> Void) {
        guard !isListening else { onStarted(true); return }
        
        let sessionId = sessionId ?? UUID().uuidString
        self.sessionId = sessionId
        self.sessionStartTime = Date()
        
        Task {
            do {
                connectionStatus = "Connecting to Deepgram..."
                
                // Connect both STT sockets (system + microphone)
                multiSTT.connectAll()
                
                connectionStatus = "Starting audio capture..."
                
                // Start system audio capture
                try await startScreenCaptureWithAudio()

                // Ensure microphone permission, then start mic capture if allowed
                let micGranted = await self.ensureMicrophonePermission()
                print("🎤 DEBUG: Microphone permission granted: \(micGranted)")
                
                if micGranted {
                    do {
                        try self.startMicrophoneCapture()
                        print("✅ DEBUG: Microphone capture started successfully")
                    } catch {
                        print("❌ DEBUG: Failed to start microphone capture: \(error.localizedDescription)")
                        self.logger.error("❌ Failed to start microphone capture: \(error.localizedDescription)")
                    }
                } else {
                    print("⚠️ DEBUG: Microphone permission not granted. Continuing with system audio only.")
                    self.logger.warning("⚠️ Microphone permission not granted. Continuing with system audio only.")
                }
                
                isListening = true
                connectionStatus = "Listening..."
                
                // Start session in transcript store
                SessionTranscriptStore.shared.startListenSession(sessionId)
                
                onStarted(true)
                print("✅ Luca: Started listening with Deepgram STT")
                
            } catch {
                connectionStatus = "Error: \(error.localizedDescription)"
                onStarted(false)
                print("❌ Luca: Failed to start listening: \(error)")
            }
        }
    }

    // MARK: - Permissions
    private func ensureMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
    
    /// Stop listening and save transcript
    func stopListening() async {
        guard isListening else { return }
        
        // Prevent concurrent stop calls
        if isStopping { return }
        isStopping = true
        
        let startTime = Date()
        print("🛑 AudioCaptureManager.stopListening() started")
        
        // Mark as not listening immediately to gate re-entrancy
        isListening = false
        connectionStatus = "Stopping..."
        
        // Stop audio capture
        print("🛑 Stopping screen capture...")
        let screenCaptureStart = Date()
        await stopScreenCapture()
        let screenCaptureTime = Date().timeIntervalSince(screenCaptureStart)
        print("✅ Screen capture stopped in \(String(format: "%.2f", screenCaptureTime))s")
        
        // Finalize Deepgram connections
        print("🛑 Disconnecting Deepgram...")
        let deepgramStart = Date()
        multiSTT.disconnectAll()
        let deepgramTime = Date().timeIntervalSince(deepgramStart)
        print("✅ Deepgram disconnected in \(String(format: "%.2f", deepgramTime))s")
        
        // Stop microphone capture
        print("🛑 Stopping microphone capture...")
        let micStart = Date()
        stopMicrophoneCapture()
        let micTime = Date().timeIntervalSince(micStart)
        print("✅ Microphone stopped in \(String(format: "%.2f", micTime))s")
        
        // Clear audio buffers to free memory
        print("🛑 Clearing audio buffers...")
        let bufferStart = Date()
        accumulatingPCM.removeAll()
        micAccumulatingPCM.removeAll()
        accumulatedSamples = 0
        let bufferTime = Date().timeIntervalSince(bufferStart)
        print("✅ Audio buffers cleared in \(String(format: "%.2f", bufferTime))s")
        
        // Save transcript
        print("🛑 Finishing session...")
        let sessionStart = Date()
        await finishSession()
        let sessionTime = Date().timeIntervalSince(sessionStart)
        print("✅ Session finished in \(String(format: "%.2f", sessionTime))s")
        
        connectionStatus = "Ready"
        isStopping = false
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("✅ AudioCaptureManager.stopListening() completed in \(String(format: "%.2f", totalTime))s")
    }
    
    // MARK: - Deepgram Integration
    
    private func setupDeepgramIntegration() {
        // Connection status updates are managed locally for now
    }
    
    // MARK: - Session Management
    
    private func finishSession() async {
        guard let sessionId = sessionId,
              let _ = sessionStartTime else { return }
        
        let startTime = Date()
        print("🔄 finishSession() started for \(sessionId)")
        
        // Finalize session in transcript store
        print("🔄 Calling finalizeListenSession()...")
        let finalizeStart = Date()
        SessionTranscriptStore.shared.finalizeListenSession()
        let finalizeTime = Date().timeIntervalSince(finalizeStart)
        print("✅ finalizeListenSession() completed in \(String(format: "%.2f", finalizeTime))s")
        
        // Clear session data
        print("🔄 Clearing session data...")
        let clearStart = Date()
        self.sessionId = nil
        self.sessionStartTime = nil
        accumulatingPCM.removeAll()
        accumulatedSamples = 0
        let clearTime = Date().timeIntervalSince(clearStart)
        print("✅ Session data cleared in \(String(format: "%.2f", clearTime))s")
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("✅ Session \(sessionId) completed and saved in \(String(format: "%.2f", totalTime))s")
    }
    
    // MARK: - Audio Capture (Enhanced for Deepgram)
    
    private func startScreenCaptureWithAudio() async throws {
        logger.info("🎬 Starting audio capture...")
        
        // Get available content for screen + audio capture
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = availableContent.displays.first else {
            logger.error("❌ No display available for capture")
            throw AudioCaptureError.noDisplayAvailable
        }
        
        logger.info("🖥️ Display: \(display.width)x\(display.height)")
        
        // Check system audio devices
        let audioDevices = AVCaptureDevice.devices(for: .audio)
        logger.info("🎤 Available audio devices: \(audioDevices.count)")
        
        for device in audioDevices {
            logger.info("📱 Device: \(device.localizedName) - ID: \(device.uniqueID)")
        }
        
        // Log which applications can provide audio
        for app in availableContent.applications {
            logger.info("📱 App: \(app.applicationName) - Bundle: \(app.bundleIdentifier) - Process ID: \(app.processID)")
        }
        
        // Configure stream for screen + audio capture
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        
        // Audio capture settings (macOS 13.0+)
        if #available(macOS 13.0, *) {
            configuration.capturesAudio = true  // This captures system audio!
            configuration.sampleRate = Int(targetSampleRate)
            configuration.channelCount = 1
            configuration.excludesCurrentProcessAudio = true  // Don't capture Luca's own audio
        }
        
        if #available(macOS 13.0, *) {
            logger.info("⚙️ Stream configuration - Audio: \(configuration.capturesAudio), Sample Rate: \(configuration.sampleRate), Channels: \(configuration.channelCount)")
        } else {
            logger.info("⚙️ Stream configuration - Screen only (audio requires macOS 13.0+)")
        }
        
        // Create and start the capture stream
        screenCaptureSession = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        // Add stream outputs
        if #available(macOS 13.0, *) {
            try screenCaptureSession?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        }
        // Attach a screen output to suppress ScreenCaptureKit warnings even if we ignore frames
        try? screenCaptureSession?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        
        // Start capture
        try await screenCaptureSession?.startCapture()
        
        // Start audio flow monitoring
        checkAudioFlow()
        
        logger.info("✅ System audio capture started for Deepgram STT")
        print("✅ System audio capture started for Deepgram STT")
    }
    
    // MARK: - Audio Flow Monitoring
    
    private func checkAudioFlow() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let lastTimestamp = self.lastAudioTimestamp {
                    let timeSinceLastAudio = Date().timeIntervalSince(lastTimestamp)
                    if timeSinceLastAudio > 3.0 {
                        self.logger.warning("⚠️ No audio received for \(String(format: "%.1f", timeSinceLastAudio)) seconds")
                        self.isAudioFlowing = false
                    }
                } else {
                    self.logger.warning("⚠️ No audio has been received yet")
                    self.isAudioFlowing = false
                }
            }
        }
    }
    
    private func stopScreenCapture() async {
        guard let session = screenCaptureSession else { return }
        
        do {
            try await session.stopCapture()
            screenCaptureSession = nil
            print("✅ System audio capture stopped")
        } catch {
            print("⚠️ Error stopping screen capture: \(error)")
        }
    }
    
    // MARK: - Microphone Capture (AVAudioEngine)
    private func startMicrophoneCapture() throws {
        // Prefer AVCaptureSession to better follow Bluetooth headset mics
        stopMicrophoneCapture()
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Use default session preset for simplicity
        print("🎤 DEBUG: Configuring AVCaptureSession...")
        
        // Select best input device (prefer Bluetooth headsets when present)
        guard let device = selectInputDevice() else {
            print("❌ DEBUG: No audio capture device available")
            logger.error("❌ No audio capture device available")
            throw AudioCaptureError.audioEngineFailed
        }
        print("🎤 DEBUG: Selected microphone device: \(device.localizedName)")
        
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            logger.error("❌ Cannot add microphone input to capture session")
            throw AudioCaptureError.audioEngineFailed
        }
        session.addInput(input)
        
        let output = AVCaptureAudioDataOutput()
        let queue = DispatchQueue(label: "mic.capture.queue", qos: .userInitiated)
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            logger.error("❌ Cannot add microphone output to capture session")
            throw AudioCaptureError.audioEngineFailed
        }
        session.addOutput(output)
        
        session.commitConfiguration()
        session.startRunning()
        
        print("✅ DEBUG: AVCaptureSession started running: \(session.isRunning)")
        
        micCaptureSession = session
        micDeviceInput = input
        micDataOutput = output
        availableMics = enumerateInputDevices()
        
        // Log all CoreAudio devices for debugging
        print("🎤 DEBUG: CoreAudio device enumeration:")
        for mic in availableMics {
            print("  - \(mic.name) (\(mic.uid)) - Default: \(mic.isDefault)")
        }
        
        print("✅ DEBUG: Microphone capture setup complete - device: \(device.localizedName)")
        logger.info("🎤 Microphone capture started (AVCaptureSession) - device: \(device.localizedName)")
    }

    // ROBUST: Find built-in microphone using CoreAudio UID matching
    private func selectInputDevice() -> AVCaptureDevice? {
        // 1) Use CoreAudio enumeration to find a device that looks like the built-in mic
        let coreDevices = enumerateInputDevices()
        print("🎤 DEBUG: Available CoreAudio devices: \(coreDevices.map { "\($0.name) (\($0.uid))" })")
        
        // Heuristics: prefer devices whose name contains "Built-in" or "Internal"
        if let builtIn = coreDevices.first(where: { 
            $0.name.localizedCaseInsensitiveContains("built") || 
            $0.name.localizedCaseInsensitiveContains("internal") ||
            $0.name.localizedCaseInsensitiveContains("macbook")
        }) {
            print("🎤 DEBUG: Found potential built-in mic via CoreAudio: \(builtIn.name) (\(builtIn.uid))")
            
            // Try to find an AVCaptureDevice that matches the CoreAudio UID
            let avDevices = AVCaptureDevice.devices(for: .audio)
            print("🎤 DEBUG: Available AVCapture devices: \(avDevices.map { "\($0.localizedName) (\($0.uniqueID))" })")
            
            if let match = avDevices.first(where: { $0.uniqueID == builtIn.uid }) {
                print("🎤 DEBUG: Found built-in mic via CoreAudio UID -> \(match.localizedName) (\(match.uniqueID))")
                logger.info("🎤 Using built-in mic via UID: \(match.localizedName) (\(match.uniqueID))")
                return match
            } else {
                print("⚠️ DEBUG: Built-in UID found (\(builtIn.uid)) but AVCaptureDevice lookup failed — falling back.")
            }
        }
        
        // 2) If not found, try DiscoverySession for builtIn
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )
        
        if let builtInMic = discovery.devices.first {
            print("🎤 DEBUG: Using discovery found built-in microphone: \(builtInMic.localizedName) (\(builtInMic.uniqueID))")
            logger.info("🎤 Using built-in mic: \(builtInMic.localizedName)")
            return builtInMic
        }
        
        // 3) Fallback to system default input
        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            print("🎤 DEBUG: Fallback to system default input device: \(defaultDevice.localizedName) (\(defaultDevice.uniqueID))")
            logger.info("🎤 Fallback to system default input: \(defaultDevice.localizedName)")
            return defaultDevice
        }
        
        print("❌ DEBUG: No microphone device found!")
        logger.error("❌ No microphone device found")
        return nil
    }
    
    private func stopMicrophoneCapture() {
        if let session = micCaptureSession, session.isRunning {
            session.stopRunning()
        }
        micCaptureSession = nil
        micDeviceInput = nil
        micDataOutput = nil
        logger.info("🛑 Microphone capture stopped")
    }

    // MARK: - Device Enumeration (CoreAudio - shows Bluetooth, iPhone, virtuals)
    private func enumerateInputDevices() -> [MicDeviceInfo] {
        var dataSize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }
        
        // Get default input device id
        var defaultInputId = AudioDeviceID(0)
        var defSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defAddr, 0, nil, &defSize, &defaultInputId)
        
        var results: [MicDeviceInfo] = []
        for devId in deviceIDs {
            // Check if device has input scope streams
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamsSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(devId, &streamAddr, 0, nil, &streamsSize) != noErr || streamsSize == 0 {
                continue
            }
            // Name
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectGetPropertyData(devId, &nameAddr, 0, nil, &nameSize, &name)
            
            // UID
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectGetPropertyData(devId, &uidAddr, 0, nil, &uidSize, &uid)
            
            let info = MicDeviceInfo(
                id: (uid as String),
                uid: (uid as String),
                name: (name as String),
                isDefault: devId == defaultInputId
            )
            results.append(info)
        }
        // Sort default first, then by name
        results.sort { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return results
    }
    
    private func processMicBuffer(_ srcBuffer: AVAudioPCMBuffer, sourceFormat: AVAudioFormat) {
        // Gate processing while paused
        if OverlayStateManager.shared.isPausedListening {
            return
        }
        guard isListening else { return }
        
        if micConverter == nil || micConverter?.inputFormat != sourceFormat {
            micConverter = AVAudioConverter(from: sourceFormat, to: dgTargetFormat)
            if micConverter == nil {
                print("❌ DEBUG: Failed to create Mic→DG converter for format: SR=\(sourceFormat.sampleRate), Ch=\(sourceFormat.channelCount), Format=\(sourceFormat.commonFormat.rawValue)")
                logger.error("❌ Failed to create Mic→DG converter for format: SR=\(sourceFormat.sampleRate), Ch=\(sourceFormat.channelCount), Format=\(sourceFormat.commonFormat.rawValue)")
                
                // Try to create a more flexible converter for Bluetooth devices
                let flexibleTargetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: sourceFormat.sampleRate, // Use source sample rate
                    channels: 1,
                    interleaved: true
                )
                
                if let flexibleFormat = flexibleTargetFormat {
                    micConverter = AVAudioConverter(from: sourceFormat, to: flexibleFormat)
                    if micConverter != nil {
                        print("🔁 DEBUG: Created flexible Mic→DG converter for Bluetooth: SR=\(sourceFormat.sampleRate)")
                        logger.info("🔁 Created flexible Mic→DG converter for Bluetooth: SR=\(sourceFormat.sampleRate)")
                    } else {
                        print("❌ DEBUG: Even flexible converter failed")
                        return
                    }
                } else {
                    print("❌ DEBUG: Could not create flexible target format")
                    return
                }
            } else {
                print("🔁 DEBUG: Created Mic→DG converter: src sr=\(sourceFormat.sampleRate), ch=\(sourceFormat.channelCount), format=\(sourceFormat.commonFormat.rawValue)")
                logger.info("🔁 Created Mic→DG converter: src sr=\(sourceFormat.sampleRate), ch=\(sourceFormat.channelCount), format=\(sourceFormat.commonFormat.rawValue)")
            }
        }
        guard let converter = micConverter else { 
            logger.error("❌ Mic converter is nil")
            return 
        }
        
        let frameCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * dgTargetFormat.sampleRate / sourceFormat.sampleRate) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: dgTargetFormat, frameCapacity: frameCapacity) else { return }
        
        var convError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuffer
        }
        converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
        if let e = convError {
            logger.error("❌ Mic convert error: \(e.localizedDescription)")
            logger.error("❌ Conversion details - Input: SR=\(sourceFormat.sampleRate), Ch=\(sourceFormat.channelCount), Format=\(sourceFormat.commonFormat.rawValue)")
            logger.error("❌ Conversion details - Output: SR=\(self.dgTargetFormat.sampleRate), Ch=\(self.dgTargetFormat.channelCount), Format=\(self.dgTargetFormat.commonFormat.rawValue)")
            return
        }
        
        guard let ch = outBuffer.int16ChannelData else { return }
        let sampleCount = Int(outBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: ch[0], count: sampleCount))
        let sampleData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        
        // Calculate audio level for debugging
        let audioLevel = calculateAudioLevel(samples: samples)
        if audioLevel > -50.0 { // Only log when there's actual sound
            print("🎤 DEBUG: Microphone audio level: \(audioLevel) dB")
        }
        
        micAccumulatingPCM.append(sampleData)
        while micAccumulatingPCM.count >= chunkSizeBytes {
            let chunk = micAccumulatingPCM.prefix(chunkSizeBytes)
            micAccumulatingPCM.removeFirst(chunkSizeBytes)
            logger.debug("🎤 Sending microphone audio chunk: \(chunk.count) bytes to Deepgram")
            multiSTT.sendAudioData(Data(chunk), for: .microphone)
        }
    }

    private func processMicCMSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Gate processing while paused
        if OverlayStateManager.shared.isPausedListening {
            return
        }
        guard isListening else { return }
        print("🎤 DEBUG: Processing microphone sample buffer")
        
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { 
            print("❌ DEBUG: No format description in mic sample buffer")
            logger.error("❌ No format description in mic sample buffer")
            return 
        }
        var asbd = asbdPtr.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd) else { 
            print("❌ DEBUG: Failed to create AVAudioFormat from mic sample")
            logger.error("❌ Failed to create AVAudioFormat from mic sample")
            return 
        }
        
        // Log Bluetooth device audio format for debugging
        print("🎤 DEBUG: Mic audio format - SR: \(sourceFormat.sampleRate), Ch: \(sourceFormat.channelCount), Format: \(sourceFormat.commonFormat.rawValue)")
        logger.info("🎤 Mic audio format - SR: \(sourceFormat.sampleRate), Ch: \(sourceFormat.channelCount), Format: \(sourceFormat.commonFormat.rawValue)")
        
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return }
        srcBuffer.frameLength = frameCount
        let cmStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frameCount), into: srcBuffer.mutableAudioBufferList)
        if cmStatus != noErr { return }
        
        processMicBuffer(srcBuffer, sourceFormat: sourceFormat)
    }

    // MARK: - Audio Processing (from screen capture)
    
    private func processAudioFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Gate processing while paused
        if OverlayStateManager.shared.isPausedListening {
            return
        }
        guard isListening else { return }
        
        // 🔍 DEBUG: Log every audio buffer received
        logger.debug("🎵 Audio buffer received - timestamp: \(Date())")
        lastAudioTimestamp = Date()
        isAudioFlowing = true
        
        // Discover source format from CMSampleBuffer
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            logger.error("❌ No audio format description")
            return
        }
        var asbd = asbdPtr.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd) else {
            logger.error("❌ Failed to create source AVAudioFormat")
            return
        }
        scInputFormat = sourceFormat
        
        // Build an AVAudioPCMBuffer and copy PCM from CMSampleBuffer safely
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            logger.error("❌ Failed to allocate source AVAudioPCMBuffer")
            return
        }
        srcBuffer.frameLength = frameCount
        // Use CoreMedia to copy PCM correctly (handles interleaved/planar and channel counts)
        let cmStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: srcBuffer.mutableAudioBufferList
        )
        if cmStatus != noErr {
            logger.error("❌ Failed to copy PCM into AVAudioPCMBuffer (status: \(cmStatus))")
            return
        }
        
        // Create or reuse converter to 16k mono Int16
        if scToDgConverter == nil || scToDgConverter?.inputFormat != sourceFormat {
            scToDgConverter = AVAudioConverter(from: sourceFormat, to: dgTargetFormat)
            logger.info("🔁 Created SC→DG converter: src sr=\(sourceFormat.sampleRate), ch=\(sourceFormat.channelCount), fmt=\(sourceFormat.commonFormat.rawValue) → 16k mono int16")
        }
        guard let converter = scToDgConverter,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: dgTargetFormat, frameCapacity: frameCount) else {
            logger.error("❌ Converter or output buffer unavailable")
            return
        }
        
        var convError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuffer
        }
        converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
        if let e = convError {
            logger.error("❌ Audio convert error: \(e.localizedDescription)")
            return
        }
        
        // Extract converted Int16 samples
        guard let ch = outBuffer.int16ChannelData else {
            logger.error("❌ No int16 channel data after conversion")
            return
        }
        let sampleCount = Int(outBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: ch[0], count: sampleCount))
        let sampleData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        accumulatingPCM.append(sampleData)
        accumulatedSamples += samples.count
        
        // Audio level for debug (converted domain)
        let audioLevel = calculateAudioLevel(samples: samples)
        DispatchQueue.main.async { self.audioLevelDebug = audioLevel }
        logger.debug("🔊 Audio level: \(audioLevel) dB, Samples: \(samples.count), Accum: \(self.accumulatingPCM.count) bytes")
        
        // Ensure 16-bit alignment
        assert(accumulatingPCM.count % 2 == 0, "PCM buffer misaligned (expected even number of bytes)")
        
        // Chunk and send (50ms = 1600 bytes @ 16k mono int16)
        while accumulatingPCM.count >= chunkSizeBytes {
            let chunk = accumulatingPCM.prefix(chunkSizeBytes)
            accumulatingPCM.removeFirst(chunkSizeBytes)
            let dataChunk = Data(chunk)
            multiSTT.sendAudioData(dataChunk, for: .system)
            logger.debug("📦 Enqueued/sent audio chunk to Deepgram - size: \(chunk.count) bytes")
        }
        
        // Voice activity detection (converted samples)
        let rms = calculateRMS(samples)
        if rms > voiceThreshold {
            lastVoiceActivity = Date()
            lastNonSilenceAt = Date()
            logger.debug("🎤 Voice activity detected - RMS: \(rms)")
        }
    }
    
    // MARK: - Audio Level Calculation
    
    private func calculateAudioLevel(samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return -100.0 }
        
        let sum = samples.reduce(0.0) { result, sample in
            return result + (Float(sample) * Float(sample))
        }
        
        let rms = sqrt(sum / Float(samples.count))
        let db = 20.0 * log10(rms / 32767.0)
        
        return db
    }
    
    private func calculateRMS(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        // Convert to Double first to avoid Int16 overflow, then square
        // Use a more robust approach to prevent any potential overflow
        var sum: Double = 0.0
        for sample in samples {
            let sampleDouble = Double(sample)
            sum += sampleDouble * sampleDouble
        }
        
        let rms = sqrt(sum / Double(samples.count))
        return Float(rms)
    }
    
    // MARK: - Force Cleanup (for app termination)
    
    func forceCleanup() {
        print("🔒 Force cleanup requested - stopping all audio capture")
        Task {
            await stopListening()
        }
        
        // Additional force cleanup for app termination
        Task {
            // Force stop screen capture if still running
            if let session = screenCaptureSession {
                try? await session.stopCapture()
                screenCaptureSession = nil
            }
            
            // Force stop audio engine
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            
            // Force disconnect Deepgram (both sources)
            multiSTT.disconnectAll()
            
            print("✅ Force cleanup completed")
        }
    }

    // MARK: - Simplified Device Selection (always use built-in microphone)
}

// MARK: - SCStreamDelegate

@MainActor
extension AudioCaptureManager: @preconcurrency SCStreamDelegate, @preconcurrency SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            processAudioFromSampleBuffer(sampleBuffer)
        case .screen:
            // Handle screen updates if needed
            break
        case .microphone:
            // Handle microphone input if needed
            break
        @unknown default:
            print("⚠️ Unknown sample buffer type: \(type)")
        }
    }
    
    // AVCaptureAudioDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processMicCMSampleBuffer(sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ Screen capture stream stopped with error: \(error)")
        isRunning = false
    }
}

// MARK: - Audio Capture Errors

enum AudioCaptureError: Error, LocalizedError {
    case noDisplayAvailable
    case permissionDenied
    case audioEngineFailed
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available for capture"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .audioEngineFailed:
            return "Audio engine failed to start"
        }
    }
}