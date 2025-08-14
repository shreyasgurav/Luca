import Foundation
import AppKit
import Vision

@MainActor
final class ScreenOCRManager {
    static let shared = ScreenOCRManager()

    private var timer: DispatchSourceTimer?
    private var isRunning: Bool = false
    private var lastDigest: String = ""

    func start(captureEvery seconds: TimeInterval = 1.0,
               excludeWindow: NSWindow? = nil,
               onText: @escaping (String) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        lastDigest = ""

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "screen.ocr.timer"))
        timer.schedule(deadline: .now() + seconds, repeating: seconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning else { return }
                // Capture on main thread due to API constraints
                let jpeg = ScreenshotManager.captureFullScreen(excludeWindow: excludeWindow)
                guard let jpeg else { return }

                // Build VNImageRequestHandler
                let handler = VNImageRequestHandler(data: jpeg, options: [:])
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = [Locale.current.identifier]
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.02

                do {
                    try handler.perform([request])
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines: [String] = observations.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }

                    // Deduplicate by simple digest to avoid repeating identical frames
                    let digest = String(text.hashValue)
                    guard digest != self.lastDigest else { return }
                    self.lastDigest = digest
                    onText(text)
                } catch {
                    // Silent fail for now
                }
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }
}


