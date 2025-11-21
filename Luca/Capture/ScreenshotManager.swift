import AppKit
import ScreenCaptureKit
import VideoToolbox
import Vision
import CoreGraphics

final class ScreenshotManager {
    // Cache the last resolved SCDisplay to avoid repeated SCShareableContent scans
    private static var cachedDisplayID: CGDirectDisplayID?
    private static var cachedSCDisplay: SCDisplay?
    private static var lastDisplayLookupAt: TimeInterval = 0

    // MARK: - Full capture (your original function, mostly unchanged)
    static func captureFullScreen(excludeWindow: NSWindow? = nil) -> Data? {
        // Ensure we're on the main thread for UI API access«
        dispatchPrecondition(condition: .onQueue(.main))
        guard let mainScreen = NSScreen.main,
              let screenNumber = (mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            print("❌ Could not find main screen")
            return nil
        }

        let displayID = CGDirectDisplayID(screenNumber)

        // Reuse cached SCDisplay where possible (refresh every 5 seconds or on display change)
        let now = Date().timeIntervalSince1970
        if ScreenshotManager.cachedSCDisplay == nil || ScreenshotManager.cachedDisplayID != displayID || (now - ScreenshotManager.lastDisplayLookupAt) > 5 {
            let semaphore = DispatchSemaphore(value: 0)
            var found: SCDisplay?
            Task {
                do {
                    let content = try await SCShareableContent.current
                    found = content.displays.first(where: { $0.displayID == displayID })
                } catch {
                    print("❌ SCShareableContent error: \(error)")
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1.0)
            ScreenshotManager.cachedSCDisplay = found
            ScreenshotManager.cachedDisplayID = displayID
            ScreenshotManager.lastDisplayLookupAt = now
        }

        guard let display = ScreenshotManager.cachedSCDisplay else {
            print("❌ Could not find SCDisplay")
            return nil
        }

        print("📸 Capturing full screen: \(display.width) x \(display.height)")

        // Exclude the response overlay window if provided
        var excludedWindows: [SCWindow] = []
        if let excludeWindow = excludeWindow {
            // Get window number on main thread FIRST
            let windowNumberToExclude = CGWindowID(excludeWindow.windowNumber)

            // Find all windows to exclude the overlay
            let windowSemaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    let content = try await SCShareableContent.current
                    excludedWindows = content.windows.filter { $0.windowID == windowNumberToExclude }
                } catch {
                    print("❌ Could not get windows: \(error)")
                }
                windowSemaphore.signal()
            }
            _ = windowSemaphore.wait(timeout: .now() + 0.3)
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        // Downscale to speed up capture and encoding (preserve aspect ratio)
        let sourceWidth = CGFloat(display.width)
        let sourceHeight = CGFloat(display.height)
        let maxDimension: CGFloat = 1600
        let scale = min(1.0, maxDimension / max(sourceWidth, sourceHeight))
        let targetWidth = Int((sourceWidth * scale).rounded(.down))
        let targetHeight = Int((sourceHeight * scale).rounded(.down))
        config.width = max(640, targetWidth)
        config.height = max(360, targetHeight)
        config.queueDepth = 1
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        if #available(macOS 13.0, *) {
            config.scalesToFit = true
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        }

        let captureSemaphore = DispatchSemaphore(value: 0)
        var capturedImage: CGImage?

        let collector = SingleFrameCollector { cgImage in
            capturedImage = cgImage
            captureSemaphore.signal()
        }

        do {
            let stream = try SCStream(filter: filter, configuration: config, delegate: collector)
            try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: collector.queue)
            try stream.startCapture()

            // Use a single background queue for all semaphore operations to avoid QoS inversion
            let captureQueue = DispatchQueue.global(qos: .userInitiated)
            
            // Stop as soon as we get a frame or after a short timeout
            captureQueue.async {
                let result = captureSemaphore.wait(timeout: .now() + 0.7)
                if result == .timedOut {
                    print("⌛️ Capture timed out at low latency threshold; stopping stream")
                }
                stream.stopCapture()
            }

            // Wait briefly for the first frame on the same QoS queue
            let waitResult = captureQueue.sync {
                return captureSemaphore.wait(timeout: .now() + 0.8)
            }
            if waitResult == .timedOut {
                print("⌛️ Main capture wait timed out")
            }
        } catch {
            print("❌ Screen capture error: \(error)")
            return nil
        }

        guard let image = capturedImage else {
            print("❌ No image captured")
            return nil
        }

        // Convert to JPEG (slightly higher compression for speed + smaller payload)
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
            print("❌ JPEG conversion failed")
            return nil
        }

        print("✅ Screenshot captured: \(jpeg.count) bytes")
        return jpeg
    }
}

// ------------------------------------------------------------------
// Probe helpers: cheap checks to decide if a capture would be useful
// ------------------------------------------------------------------
extension ScreenshotManager {
    /// Quick probe to determine whether a screen capture is likely to contain
    /// useful content for a debugging / problem-solving request.
    ///
    /// - Returns: (useful, reason). Useful==true means "go ahead and capture".
    static func probeScreenForUsefulness(excludeWindow: NSWindow? = nil, minTextCandidates: Int = 1, timeout: TimeInterval = 1.0) -> (useful: Bool, reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))

        // 0) quick preflight for screen-recording permission (if available)
        if #available(macOS 10.15, *) {
            // CGPreflightScreenCaptureAccess exists on macOS and is lightweight
            if !CGPreflightScreenCaptureAccess() {
                return (false, "screen-recording permission not granted")
            }
        }

        // 1) Query SCShareableContent to see windows
        var content: SCShareableContent?
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                content = try await SCShareableContent.current
            } catch {
                print("❌ SCShareableContent error (probe): \(error)")
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.8)

        guard let sc = content else {
            return (false, "couldn't query screen content")
        }

        // If there are visible windows that are likely to contain text (editors, browsers, terminals),
        // treat as useful.
        let usefulWindows = sc.windows.filter { w in
            // Filter out system windows (menu bar, etc.) and hidden windows
            guard let bundleId = w.owningApplication?.bundleIdentifier else { return false }
            if bundleId.contains("windowserver") { return false }
            if w.isOnScreen == false { return false }
            // Some windows have empty titles but are still useful (terminals). Use bundleIdentifier hint.
            return true
        }

        if !usefulWindows.isEmpty {
            // If all windows are just the desktop or screensaver, this will be empty,
            // but typically there will be at least one app window.
            return (true, "found visible windows")
        }

        // 2) If no visible windows, capture a tiny thumbnail and run a fast OCR pass
        guard let smallImage = captureThumbnail(excludeWindow: excludeWindow, maxDimension: 640, timeout: timeout) else {
            return (false, "no thumbnail captured")
        }

        // Run Vision text recognition quickly
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: smallImage, options: [:])
        do {
            try handler.perform([request])
            let results = request.results ?? []
            let candidates = results.compactMap { obs in
                obs.topCandidates(1).first?.string
            }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let nonEmpty = candidates.filter { $0.count >= 3 } // short heuristics
            if nonEmpty.count >= minTextCandidates {
                return (true, "thumbnail OCR detected text")
            } else {
                return (false, "thumbnail OCR found no readable text")
            }
        } catch {
            print("❌ OCR failed: \(error)")
            return (false, "OCR failure")
        }
    }

    /// Capture a small thumbnail (CGImage) quickly for probing (not JPEG).
    /// This uses a separate small collector to avoid changing your main capture code.
    private static func captureThumbnail(excludeWindow: NSWindow? = nil, maxDimension: Int = 640, timeout: TimeInterval = 0.7) -> CGImage? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let mainScreen = NSScreen.main,
              let screenNumber = (mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            print("❌ Could not find main screen (thumbnail)")
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber)

        // Get display object (fresh)
        var scDisplay: SCDisplay?
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let content = try await SCShareableContent.current
                scDisplay = content.displays.first(where: { $0.displayID == displayID })
            } catch {
                print("❌ SCShareableContent error (thumbnail): \(error)")
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.6)
        guard let display = scDisplay else { return nil }

        // Exclude overlay if requested
        var excludedWindows: [SCWindow] = []
        if let excludeWindow = excludeWindow {
            let windowNumberToExclude = CGWindowID(excludeWindow.windowNumber)
            let sem2 = DispatchSemaphore(value: 0)
            Task {
                do {
                    let content = try await SCShareableContent.current
                    excludedWindows = content.windows.filter { $0.windowID == windowNumberToExclude }
                } catch {
                    // ignore
                }
                sem2.signal()
            }
            _ = sem2.wait(timeout: .now() + 0.2)
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        // compute small size preserving aspect ratio
        let sourceWidth = CGFloat(display.width)
        let sourceHeight = CGFloat(display.height)
        let scale = min(1.0, CGFloat(maxDimension) / max(sourceWidth, sourceHeight))
        let targetWidth = Int((sourceWidth * scale).rounded(.down))
        let targetHeight = Int((sourceHeight * scale).rounded(.down))
        config.width = max(200, targetWidth)
        config.height = max(120, targetHeight)
        config.queueDepth = 1
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        if #available(macOS 13.0, *) {
            config.scalesToFit = true
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        }

        let captureSemaphore = DispatchSemaphore(value: 0)
        var capturedImage: CGImage?

        let collector = ThumbnailCollector { cgImage in
            capturedImage = cgImage
            captureSemaphore.signal()
        }

        do {
            let stream = try SCStream(filter: filter, configuration: config, delegate: collector)
            try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: collector.queue)
            try stream.startCapture()

            // Use a single background queue for all semaphore operations to avoid QoS inversion
            let captureQueue = DispatchQueue.global(qos: .userInitiated)
            
            captureQueue.async {
                let result = captureSemaphore.wait(timeout: .now() + timeout)
                if result == .timedOut {
                    print("⌛️ Thumbnail capture timed out")
                }
                stream.stopCapture()
            }

            // Wait for capture completion on the same QoS queue
            let waitResult = captureQueue.sync {
                return captureSemaphore.wait(timeout: .now() + timeout + 0.1)
            }
            if waitResult == .timedOut {
                print("⌛️ Thumbnail main wait timed out")
            }
        } catch {
            print("❌ Thumbnail capture error: \(error)")
            return nil
        }

        return capturedImage
    }
}

// ------------------------------------------------------------------
// Collectors
// ------------------------------------------------------------------
private final class SingleFrameCollector: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "screenshot.capture.queue", qos: .userInitiated)
    private let onFrame: (CGImage) -> Void
    private var emitted = false

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, !emitted, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var cgImageOut: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageOut)

        if let cgImageOut {
            emitted = true
            onFrame(cgImageOut)
        } else if status != noErr {
            print("❌ VTCreateCGImageFromCVPixelBuffer status: \(status)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ SCStream stopped with error: \(error)")
    }
}

/// Separate, small collector for thumbnailing (keeps concerns separate)
private final class ThumbnailCollector: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "screenshot.thumbnail.queue", qos: .userInitiated)
    private let onFrame: (CGImage) -> Void
    private var emitted = false

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, !emitted, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var cgImageOut: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageOut)

        if let cgImageOut {
            emitted = true
            onFrame(cgImageOut)
        } else if status != noErr {
            print("❌ VTCreateCGImageFromCVPixelBuffer (thumbnail) status: \(status)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ Thumbnail SCStream stopped with error: \(error)")
    }
}
