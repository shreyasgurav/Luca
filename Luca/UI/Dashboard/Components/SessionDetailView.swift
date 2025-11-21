import SwiftUI

// Simple Tags Flow View for macOS compatibility
struct TagsFlowView: View {
    let tags: [String]
    let spacing: CGFloat = 8
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(chunkedTags.enumerated()), id: \.offset) { index, tagRow in
                HStack(spacing: spacing) {
                    ForEach(tagRow, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
    }
    
    private var chunkedTags: [[String]] {
        // Simple horizontal flow - could be enhanced with proper wrapping logic
        // For now, just split into rows of 3-4 tags
        let tagsPerRow = 4
        var result: [[String]] = []
        
        for i in stride(from: 0, to: tags.count, by: tagsPerRow) {
            let endIndex = min(i + tagsPerRow, tags.count)
            result.append(Array(tags[i..<endIndex]))
        }
        
        return result
    }
}

struct SessionDetailView: View {
    let session: ListenSession
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    @State private var activeTab: Tab = .summary
    @State private var editableTitle: String = ""
    @State private var notesText: String = ""
    @State private var generatedNotes: String = ""
    @State private var detailedNotes: String = ""
    @State private var isGeneratingNotes: Bool = false
    @State private var notesError: String? = nil
    
    enum Tab { case summary, transcript }
    
    private var sessionTitle: String {
        return (session.title?.isEmpty == false) ? session.title! : session.generatedTitle
    }
    
    
    private var durationText: String {
        guard let duration = session.duration else { return "Active Session" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    // Get the latest session data from the store
    private var currentSession: ListenSession? {
        transcriptStore.sessions.first { $0.id == session.id }
    }
    
    // Bind to session-provided insights (use current session data)
    private var highlights: [String] { currentSession?.highlights ?? session.highlights }
    private var actionItems: [String] { currentSession?.actionItems ?? session.actionItems }
    private var tags: [String] { currentSession?.tags ?? session.tags }
    private var sessionNotes: String? { currentSession?.notes ?? transcriptStore.sessions.first(where: { $0.id == session.id })?.notes }
    private var sessionSummary: String? { currentSession?.summary ?? transcriptStore.sessions.first(where: { $0.id == session.id })?.summary }
    
    // Manual notes from listen panel
    private var manualNotesText: String {
        UserDefaults.standard.string(forKey: "ListenPanelNotes") ?? ""
    }

    // Parsed structured notes from generatedNotes (if JSON)
    private struct GeneratedNotesPayload: Decodable {
        let summary: String?
        let notes: String?
        let highlights: [String]?
        let action_items: [String]?
        let decisions: [String]?
        let unanswered_questions: [String]?
        let tags: String? // Can be string or array, handle both
    }

    private var parsedGenerated: GeneratedNotesPayload? {
        guard !generatedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let data = generatedNotes.data(using: .utf8) ?? Data()
        do {
            return try JSONDecoder().decode(GeneratedNotesPayload.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func parseGeneratedNotes(_ jsonString: String) -> GeneratedNotesPayload? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(GeneratedNotesPayload.self, from: data)
        } catch {
            print("Failed to parse generated notes JSON: \(error)")
            return nil
        }
    }
    
    // Derive extra key points from notes to include in highlights
    private var derivedHighlights: [String] {
        let base = highlights
        let extras = notesKeyPoints
        if extras.isEmpty { return base }
        var seen = Set<String>()
        var merged: [String] = []
        for p in base + extras {
            if seen.insert(p).inserted { merged.append(p) }
        }
        return merged
    }

    private var combinedHighlights: [String] {
        if let parsed = parsedGenerated, let hs = parsed.highlights, !hs.isEmpty {
            return unique(base: hs)
        }
        return derivedHighlights
    }

    private var combinedActionItems: [String] {
        if let parsed = parsedGenerated, let items = parsed.action_items, !items.isEmpty {
            return unique(base: items)
        }
        return actionItems
    }

    private var combinedTags: [String] {
        if let parsed = parsedGenerated, let t = parsed.tags, !t.isEmpty {
            // Split comma-separated tags string into array
            let parsedTags = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return unique(base: tags + parsedTags)
        }
        return tags
    }

    private var combinedDecisions: [String] {
        if let parsed = parsedGenerated, let d = parsed.decisions, !d.isEmpty {
            return unique(base: d)
        }
        return decisionsMade
    }

    private var combinedUnanswered: [String] {
        if let parsed = parsedGenerated, let q = parsed.unanswered_questions, !q.isEmpty {
            return unique(base: q)
        }
        return unansweredQuestions
    }

    private func unique(base: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for v in base where seen.insert(v).inserted { result.append(v) }
        return result
    }
    
    private var notesKeyPoints: [String] {
        let lines = notesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let bullets = lines.compactMap { line -> String? in
            if line.hasPrefix("-") || line.hasPrefix("•") || line.range(of: "^\\d+\\. ", options: .regularExpression) != nil {
                return line.trimmingCharacters(in: CharacterSet(charactersIn: "-• "))
            }
            if line.count <= 120 { return line }
            return nil
        }
        return bullets
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (centered container, left-aligned text)
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    TextField("Session Title", text: $editableTitle, onCommit: saveEditedTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Single toggle button
                    Button(action: { 
                        activeTab = (activeTab == .summary) ? .transcript : .summary 
                    }) {
                        Text(activeTab == .summary ? "Transcripts" : "Notes")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
                .frame(maxWidth: 560, alignment: .leading)
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Content
            Group {
                if activeTab == .summary {
                    ScrollView {
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 24) {
                            // Single free-form notes section (topic-structured Markdown)
                            detailedNotesView
                            
                            // Manual notes from listen panel (if user has typed anything)
                            if !manualNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Notes")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    Text(manualNotesText)
                                        .font(.body)
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                        .padding(12)
                                        .background(Color(.textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(.separatorColor), lineWidth: 1)
                                        )
                                }
                            }
                            }
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                } else {
                    ScrollView {
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 16) {
                            // Transcript Header
                            HStack {
                                Text("Full Transcript")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Button(action: copyTranscript) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                        Text("Copy")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.borderless)
                            }
                            
                            // Transcript Content
                            if !session.fullTranscript.isEmpty {
                                Text(session.fullTranscript)
                                    .font(.body)
                                    .lineSpacing(6)
                                    .textSelection(.enabled)
                                    .padding(20)
                                    .background(Color(.textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(.separatorColor), lineWidth: 1)
                                    )
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "waveform.slash")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    
                                    Text("No transcript available")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    
                                    Text("This session doesn't contain any transcribed content.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(40)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            }
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            // Load detailed notes for this session with safety check
            guard !session.id.isEmpty else {
                print("⚠️ Invalid session ID, skipping notes load")
                return
            }
            
            // Initialize editable title
            editableTitle = session.title ?? session.generatedTitle

            // Load notes from current session data (will refresh when store updates)
            updateNotesFromCurrentSession()
        }
        .onChange(of: transcriptStore.sessions) { _ in
            // Refresh notes when sessions are updated
            updateNotesFromCurrentSession()
        }
    }
    
    private func updateNotesFromCurrentSession() {
        // Load notes from current session data
        detailedNotes = sessionNotes ?? sessionSummary ?? ""
        
        print("📝 Session details updated for session: \(session.id)")
        if !detailedNotes.isEmpty {
            print("📝 Loaded detailed notes: \(detailedNotes.prefix(100))...")
        } else {
            print("📝 No detailed notes found for session: \(session.id)")
        }
    }
    
    private func saveEditedTitle() {
        let newTitle = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        SessionTranscriptStore.shared.updateSessionTitle(sessionId: session.id, to: newTitle)
    }
    private var highlightsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights / Key Points")
                .font(.title2)
                .fontWeight(.semibold)
            
            let points = combinedHighlights
            if points.isEmpty {
                Text("No highlights available")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.body)
                                .padding(.top, 2)
                            Text(point)
                                .font(.body)
                                .lineSpacing(4)
                        }
                    }
                }
            }
        }
    }
    
    // Action Items View
    private var actionItemsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action Items")
                .font(.title2)
                .fontWeight(.semibold)
            
            let items = combinedActionItems
            if items.isEmpty {
                Text("No action items found")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.body)
                                .padding(.top, 2)
                            Text(item)
                                .font(.body)
                                .lineSpacing(4)
                        }
                    }
                }
            }
        }
    }
    
    // Tags View
    private var tagsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.title2)
                .fontWeight(.semibold)
            
            let allTags = combinedTags
            if allTags.isEmpty {
                Text("No tags")
                    .foregroundColor(.secondary)
            } else {
                TagsFlowView(tags: allTags)
            }
        }
    }

    // Decisions Made View
    private var decisionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decisions Made")
                .font(.title2)
                .fontWeight(.semibold)
            
            let decisions = combinedDecisions
            if decisions.isEmpty {
                Text("No decisions detected")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(decisions, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.body)
                                .padding(.top, 2)
                            Text(item)
                                .font(.body)
                                .lineSpacing(4)
                        }
                    }
                }
            }
        }
    }

    // Unanswered Questions View
    private var unansweredQuestionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unanswered Questions")
                .font(.title2)
                .fontWeight(.semibold)
            
            let questions = combinedUnanswered
            if questions.isEmpty {
                Text("No open questions detected")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(questions, id: \.self) { q in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.body)
                                .padding(.top, 2)
                            Text(q)
                                .font(.body)
                                .lineSpacing(4)
                        }
                    }
                }
            }
        }
    }
    
    // NOTE: Removed notesGenerationView - redundant section that was causing duplicate Notes titles
    private var removedNotesGenerationView: some View {
        EmptyView()
    }
    
    // MARK: - Detailed Notes View (Most Important Section)
    private var detailedNotesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !detailedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(parsedNoteSections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // Render paragraphs and bullet groups
                            ForEach(section.blocks.indices, id: \.self) { idx in
                                let block = section.blocks[idx]
                                if case .bullets(let items) = block {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(items, id: \.self) { item in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                    .padding(.top, 2)
                                                Text(item)
                                                    .multilineTextAlignment(.leading)
                                                    .textSelection(.enabled)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                } else if case .paragraph(let text) = block {
                                    Text(text)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No notes available for this meeting")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text("Notes will be automatically generated when the session ends.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Lightweight Markdown section parser (## Headings -> blocks)
    private struct NoteSection: Hashable { let title: String; let blocks: [NoteBlock] }
    private enum NoteBlock: Hashable { case paragraph(String); case bullets([String]) }

    private var parsedNoteSections: [NoteSection] {
        // Split by headings beginning with "## "
        let lines = detailedNotes.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [NoteSection] = []
        var currentTitle: String = "General"
        var currentLines: [String] = []
        func flush() {
            guard !currentLines.isEmpty else { return }
            sections.append(NoteSection(title: currentTitle, blocks: blocks(from: currentLines)))
        }
        for line in lines {
            if line.hasPrefix("## ") {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return sections
    }

    private func blocks(from lines: [String]) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var i = 0
        while i < lines.count {
            // Skip leading empties
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
            guard i < lines.count else { break }
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                var items: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    let item = lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)
                    items.append(String(item))
                    i += 1
                }
                blocks.append(.bullets(items))
            } else {
                var paraLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    paraLines.append(lines[i])
                    i += 1
                }
                let text = paraLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.paragraph(text)) }
            }
        }
        return blocks
    }
    
    
    // NOTE: Removed manual generateNotes() function
    // Notes are now automatically generated when session ends via SessionTranscriptStore
    // This prevents duplicate API calls and improves performance
    
    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.fullTranscript, forType: .string)
    }

    // MARK: - Transcript Parsing Heuristics
    private var decisionsMade: [String] {
        extractDecisions(from: session.fullTranscript)
    }
    
    private var unansweredQuestions: [String] {
        extractQuestions(from: session.fullTranscript)
    }
    
    private func extractDecisions(from transcript: String) -> [String] {
        guard !transcript.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: "\n.?!")
        let rawParts = transcript.components(separatedBy: separators)
        let keywords = [
            "we will", "we'll", "let's", "decided", "decision", "agree", "agreed", "finalize", "approved", "we are going to"
        ]
        
        var seen = Set<String>()
        var results: [String] = []
        for part in rawParts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                if seen.insert(trimmed).inserted {
                    results.append(trimmed)
                }
            }
        }
        return Array(results.prefix(10))
    }
    
    private func extractQuestions(from transcript: String) -> [String] {
        guard !transcript.isEmpty else { return [] }
        var results: [String] = []
        var seen = Set<String>()
        
        let lines = transcript.components(separatedBy: CharacterSet.newlines)
        let questionStarters = ["who", "what", "when", "where", "why", "how", "which", "did", "do", "does", "can", "could", "should", "would", "will", "are", "is"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if trimmed.hasSuffix("?") || questionStarters.contains(where: { lower.hasPrefix($0 + " ") }) {
                if seen.insert(trimmed).inserted {
                    results.append(trimmed)
                }
            }
        }
        
        return Array(results.prefix(10))
    }
}

#Preview {
    SessionDetailView(session: ListenSession(
        id: "test-session",
        startTime: Date(),
        endTime: Date().addingTimeInterval(300),
        segments: [],
        summary: "This is a sample summary of the session content. It provides key insights and highlights from the conversation."
    ))
}
