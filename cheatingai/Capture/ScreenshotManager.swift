import AppKit
import ScreenCaptureKit
import VideoToolbox

final class ScreenshotManager {
    static func captureFullScreen(excludeWindow: NSWindow? = nil) -> Data? {
        // Ensure we're on the main thread for UI API access
        dispatchPrecondition(condition: .onQueue(.main))
        guard let mainScreen = NSScreen.main,
              let screenNumber = (mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            print("❌ Could not find main screen")
            return nil
        }
        
        let displayID = CGDirectDisplayID(screenNumber)
        
        // Find SCDisplay
        let semaphore = DispatchSemaphore(value: 0)
        var scDisplay: SCDisplay?
        
        Task {
            do {
                let content = try await SCShareableContent.current
                scDisplay = content.displays.first(where: { $0.displayID == displayID })
            } catch {
                print("❌ SCShareableContent error: \(error)")
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 2.0)
        
        guard let display = scDisplay else {
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
                    excludedWindows = content.windows.filter { window in
                        window.windowID == windowNumberToExclude
                    }
                } catch {
                    print("❌ Could not get windows: \(error)")
                }
                windowSemaphore.signal()
            }
            _ = windowSemaphore.wait(timeout: .now() + 1.0)
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.queueDepth = 1
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        
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
            
            _ = captureSemaphore.wait(timeout: .now() + 3.0)
            stream.stopCapture()
        } catch {
            print("❌ Screen capture error: \(error)")
            return nil
        }
        
        guard let image = capturedImage else {
            print("❌ No image captured")
            return nil
        }
        
        // Convert to JPEG
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            print("❌ JPEG conversion failed")
            return nil
        }
        
        print("✅ Screenshot captured: \(jpeg.count) bytes")
        return jpeg
    }
}

private final class SingleFrameCollector: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "screenshot.capture.queue")
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
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ SCStream stopped with error: \(error)")
    }
}
