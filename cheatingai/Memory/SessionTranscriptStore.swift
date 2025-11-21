import Foundation
import AppKit

struct SessionTranscript: Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let fileURL: URL
    let sizeBytes: Int
    let preview: String
}

@MainActor
final class SessionTranscriptStore: ObservableObject {
    static let shared = SessionTranscriptStore()
    private init() {}

    @Published private(set) var sessions: [SessionTranscript] = []

    private var baseDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Nova/Sessions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func saveTranscript(sessionId: String, transcript: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "\(sessionId)_\(timestamp).txt"
        let url = baseDir.appendingPathComponent(filename)
        do {
            try transcript.data(using: .utf8)?.write(to: url)
            // refresh list
            Task { await loadSessions() }
        } catch {
            print("❌ SessionTranscriptStore: failed to save transcript: \(error)")
        }
    }

    func loadSessions() async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            await MainActor.run { self.sessions = [] }
            return
        }
        var items: [SessionTranscript] = []
        for url in files.filter({ $0.pathExtension.lowercased() == "txt" }) {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let mod = (attrs?[.modificationDate] as? Date) ?? Date()
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let preview = String(text.prefix(240))
            let id = url.deletingPathExtension().lastPathComponent
            items.append(SessionTranscript(id: id, createdAt: mod, fileURL: url, sizeBytes: size, preview: preview))
        }
        items.sort { $0.createdAt > $1.createdAt }
        await MainActor.run { self.sessions = items }
    }

    func revealInFinder(_ item: SessionTranscript) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func delete(_ item: SessionTranscript) {
        do { try FileManager.default.removeItem(at: item.fileURL) } catch { print("⚠️ Failed to delete: \(error)") }
        Task { await loadSessions() }
    }
}


