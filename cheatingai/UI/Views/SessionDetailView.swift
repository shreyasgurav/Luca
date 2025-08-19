import SwiftUI

struct SessionDetailView: View {
    let session: SessionTranscriptStore.TranscriptSession
    @State private var fileText: String = ""
    @State private var summarySection: String = ""
    @State private var transcriptSection: String = ""
    @State private var activeTab: Tab = .summary
    
    enum Tab { case summary, transcript }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .foregroundColor(.accentColor)
                Text(session.id)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Open in Finder") { SessionTranscriptStore.shared.revealInFinder(session) }
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(fileText, forType: .string) }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Tabs
            HStack(spacing: 8) {
                Button(action: { activeTab = .summary }) {
                    Text("Summary")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeTab == .summary ? Color.accentColor.opacity(0.12) : Color.clear)
                        .foregroundColor(activeTab == .summary ? .accentColor : .primary)
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
                Button(action: { activeTab = .transcript }) {
                    Text("Transcript")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeTab == .transcript ? Color.accentColor.opacity(0.12) : Color.clear)
                        .foregroundColor(activeTab == .transcript ? .accentColor : .primary)
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
                Spacer()
                // Stubs for upcoming features
                Button("Ask follow‑up") { /* TODO: wire to conversation */ }
                Button("Re‑summarize") { /* TODO: trigger SummaryManager on this file */ }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            Group {
                if activeTab == .summary {
                    ScrollView {
                        Text(summarySection.isEmpty ? "(No summary)" : summarySection)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    ScrollView {
                        Text(transcriptSection.isEmpty ? "(No transcript)" : transcriptSection)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
        }
        .task { await loadFile() }
    }
    
    private func loadFile() async {
        guard let data = try? Data(contentsOf: session.fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        fileText = text
        // Parse SUMMARY and TRANSCRIPT sections
        let lines = text.components(separatedBy: "\n")
        if let summaryIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).uppercased() == "SUMMARY" }),
           let transcriptIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).uppercased() == "TRANSCRIPT" }) {
            let summaryBody = lines.dropFirst(summaryIdx + 1)
            let untilTranscript = summaryBody.prefix(transcriptIdx - summaryIdx - 1)
            summarySection = untilTranscript.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let transcriptBody = lines.dropFirst(transcriptIdx + 1)
            transcriptSection = transcriptBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            summarySection = ""
            transcriptSection = text
        }
    }
}

#Preview {
    SessionDetailView(session: SessionTranscriptStore.TranscriptSession(
        id: "transcript_2025-08-19_12-00-00_ABCDEFGH",
        createdAt: Date(),
        sizeBytes: 1024,
        preview: "Preview",
        fileURL: URL(fileURLWithPath: "/tmp/nonexistent.txt")
    ))
}


