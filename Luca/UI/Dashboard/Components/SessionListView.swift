import SwiftUI
import AppKit

struct SessionListView: View {
    @ObservedObject var transcriptStore: SessionTranscriptStore
    @State private var searchText = ""
    
    private var filteredSessions: [ListenSession] {
        // Only show complete sessions (sessions with generated notes)
        // For backward compatibility, treat sessions without isComplete field as complete
        let completeSessions = transcriptStore.sessions.filter { session in
            // If isComplete is explicitly false, don't show it
            // If isComplete is true or nil (missing), show it
            return session.isComplete != false
        }
        
        if searchText.isEmpty {
            return completeSessions.sorted { $0.startTime > $1.startTime }
        } else {
            return completeSessions.filter { session in
                session.fullTranscript.localizedCaseInsensitiveContains(searchText) ||
                session.summary?.localizedCaseInsensitiveContains(searchText) == true
            }.sorted { $0.startTime > $1.startTime }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sessions List
            if filteredSessions.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredSessions, id: \.id) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowContent(session: session)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowSeparatorHiddenCompat()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets()) // Remove default padding
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "waveform.slash" : "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No Sessions Yet" : "No Results Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(searchText.isEmpty ? 
                     "Start a listen session to see your transcripts here" :
                     "Try adjusting your search terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if searchText.isEmpty {
                Button("Start Listening") {
                    // TODO: Trigger listen session
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct SessionRowContent: View {
    let session: ListenSession
    @State private var isHovering = false
    @State private var showDelete = false
    @ObservedObject var transcriptStore = SessionTranscriptStore.shared
    
    private var durationText: String {
        guard let duration = session.duration else { return "Active" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    private var sessionTitle: String {
        return (session.title?.isEmpty == false) ? session.title! : session.generatedTitle
    }
    
    private var isGeneratingNotes: Bool {
        return transcriptStore.generatingNotesForSessions.contains(session.id)
    }

    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Session title only
            Text(sessionTitle)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right: Generating Notes Animation OR Date/Time OR Delete button on hover
            ZStack(alignment: .trailing) {
                if isGeneratingNotes {
                    HStack(spacing: 6) {
                        Text("Generating Notes")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        
                        // Animated dots
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 3, height: 3)
                                    .scaleEffect(isGeneratingNotes ? 1.0 : 0.5)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                        value: isGeneratingNotes
                                    )
                            }
                        }
                    }
                    .opacity(showDelete ? 0 : 1)
                    .animation(.easeInOut(duration: 0.12), value: showDelete)
                } else {
                    Text(session.startTime.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(showDelete ? 0 : 1)
                        .animation(.easeInOut(duration: 0.12), value: showDelete)
                }
                
                Button(action: {
                    confirmDelete(session)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(6)
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(showDelete ? 1 : 0)
                        .scaleEffect(showDelete ? 1 : 0.95)
                        .animation(.easeInOut(duration: 0.12), value: showDelete)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering ? Color.gray.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
                showDelete = true
            } else {
                NSCursor.pop()
                showDelete = false
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle()) // Make entire area tappable
    }
    
    private func confirmDelete(_ session: ListenSession) {
        let alert = NSAlert()
        alert.messageText = "Delete Session"
        alert.informativeText = "Are you sure you want to delete this session? This action cannot be undone."
        alert.alertStyle = .warning
        
        // Add buttons in the correct order for macOS (first button is default/primary)
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        // Set the Delete button as destructive (red)
        if let deleteButton = alert.buttons.first {
            deleteButton.hasDestructiveAction = true
            deleteButton.keyEquivalent = "\r" // Return key
        }
        
        // Set Cancel button properties
        if let cancelButton = alert.buttons.last {
            cancelButton.keyEquivalent = "\u{1b}" // Escape key
        }
        
        let response = alert.runModal()
        
        // Check which button was clicked (first button = .alertFirstButtonReturn)
        if response == .alertFirstButtonReturn {
            transcriptStore.deleteSession(session)
        }
    }
}

#Preview {
    SessionListView(transcriptStore: SessionTranscriptStore.shared)
        .frame(width: 400, height: 600)
}
