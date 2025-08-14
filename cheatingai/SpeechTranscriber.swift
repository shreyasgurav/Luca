import Foundation
import AVFoundation
import Speech

@MainActor
final class SpeechTranscriber: NSObject {
    static let shared = SpeechTranscriber()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isRunning: Bool = false

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        guard !isRunning else { return }

        requestAuthorization { [weak self] authorized in
            guard let self else { return }
            guard authorized else {
                onPartial("")
                return
            }

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(macOS 12.0, *) {
                req.requiresOnDeviceRecognition = false
                req.taskHint = .dictation
            }
            self.request = req

            self.isRunning = true
            self.task = self.recognizer?.recognitionTask(with: req) { result, error in
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(text)
                    } else {
                        // Stream partials for live feedback
                        onPartial(text)
                    }
                }
                if error != nil {
                    // End on error
                    self.stop()
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard isRunning, let request = request else { return }
        request.append(buffer)
    }

    func stop() {
        guard isRunning else { return }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRunning = false
    }
}


