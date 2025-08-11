import AppKit
import ScreenCaptureKit
import AVFoundation
import VideoToolbox
import CoreImage

struct CapturedImage {
    let cgImage: CGImage
    let jpegData: Data
    let pixelRect: CGRect
}

enum CaptureError: Error { case permissionDenied, captureFailed }

enum CaptureManager {
    static func capture(from window: NSWindow, rectInWindowCoords: CGRect, on screen: NSScreen) -> CapturedImage? {
        // Convert window rect to screen coordinates (points)
        let rectInScreenPoints = window.convertToScreen(rectInWindowCoords)
        
        // Convert to display coordinates relative to the screen origin
        let screenFrame = screen.frame
        let relativeRect = CGRect(
            x: rectInScreenPoints.origin.x - screenFrame.origin.x,
            y: rectInScreenPoints.origin.y - screenFrame.origin.y,
            width: rectInScreenPoints.width,
            height: rectInScreenPoints.height
        )
        
        // Apply backing scale factor to get pixel coordinates
        let scale = screen.backingScaleFactor
        let pixelRect = CGRect(
            x: relativeRect.origin.x * scale,
            y: relativeRect.origin.y * scale,
            width: relativeRect.width * scale,
            height: relativeRect.height * scale
        ).integral
        
        print("🔍 Debug coordinates:")
        print("  Window rect: \(rectInWindowCoords)")
        print("  Screen points: \(rectInScreenPoints)")
        print("  Screen frame: \(screenFrame)")
        print("  Relative rect: \(relativeRect)")
        print("  Scale factor: \(scale)")
        print("  Final pixel rect: \(pixelRect)")

        // Map NSScreen to SCDisplay
        guard let screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
        let targetDisplayID = CGDirectDisplayID(screenNumber)
        guard let scDisplay = ScreenCaptureHelper.findSCDisplay(matching: targetDisplayID) else { return nil }

        // First capture the entire display, then crop
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(scDisplay.width)
        config.height = Int(scDisplay.height)
        config.queueDepth = 1
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false

        let semaphore = DispatchSemaphore(value: 0)
        var fullScreenImage: CGImage?

        let collector = ScreenCaptureHelper.SingleFrameCollector { cgImage in
            fullScreenImage = cgImage
            semaphore.signal()
        }

        do {
            let stream = try SCStream(filter: filter, configuration: config, delegate: collector)
            try stream.addStreamOutput(collector, type: SCStreamOutputType.screen, sampleHandlerQueue: collector.queue)
            try stream.startCapture()
            // Wait for first frame or timeout
            _ = semaphore.wait(timeout: .now() + 2.0)
            stream.stopCapture() 
        } catch {
            NSLog("ScreenCaptureKit error: \(error.localizedDescription)")
            return nil
        }

        guard let fullImage = fullScreenImage else { 
            print("❌ Failed to capture full screen")
            return nil 
        }
        
        // Crop the desired area from the full screen capture
        print("🖼️ Full image size: \(fullImage.width) x \(fullImage.height)")
        print("✂️ Cropping to: \(pixelRect)")
        
        guard let croppedImage = fullImage.cropping(to: pixelRect) else {
            print("❌ Failed to crop image")
            return nil
        }
        
        let cgImage = croppedImage

        // Encode to JPEG
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            return nil
        }

        return CapturedImage(cgImage: cgImage, jpegData: jpeg, pixelRect: pixelRect)
    }
}

private enum ScreenCaptureHelper {
    static func findSCDisplay(matching displayID: CGDirectDisplayID) -> SCDisplay? {
        let contentSemaphore = DispatchSemaphore(value: 0)
        var found: SCDisplay?
        Task {
            do {
                let content = try await SCShareableContent.current
                found = content.displays.first(where: { $0.displayID == displayID })
            } catch {
                NSLog("SCShareableContent error: \(error.localizedDescription)")
            }
            contentSemaphore.signal()
        }
        _ = contentSemaphore.wait(timeout: .now() + 2.0)
        return found
    }

    final class SingleFrameCollector: NSObject, SCStreamOutput, SCStreamDelegate {
        let queue = DispatchQueue(label: "screen.capture.frame.queue")
        private let onFrame: (CGImage) -> Void
        private var emitted = false

        init(onFrame: @escaping (CGImage) -> Void) { self.onFrame = onFrame }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard outputType == .screen, !emitted, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            var cgImageOut: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageOut)
            if let cgImageOut {
                emitted = true
                onFrame(cgImageOut)
            }
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            NSLog("SCStream stopped with error: \(error.localizedDescription)")
        }
    }
}


