import AppKit
import Vision

enum OCRManager {
    static func recognizeText(in cgImage: CGImage, completion: @escaping (String?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error { print("OCR error: \(error)"); completion(nil); return }
            let texts = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
            completion(texts.isEmpty ? nil : texts.joined(separator: "\n"))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) } catch { print("OCR perform error: \(error)"); completion(nil) }
        }
    }
}


