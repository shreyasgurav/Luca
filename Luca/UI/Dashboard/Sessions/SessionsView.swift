import SwiftUI

struct SessionsView: View {
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    @StateObject private var authManager = AuthenticationManager.shared
    
    @State private var filteredSessions: [ListenSession] = []
    @State private var showingSessionDetail = false
    @State private var selectedSession: ListenSession?
    @State private var refreshTrigger = UUID()
    @State private var didAutoOpen = false
    @State private var isLoadingSessions = false
    @State private var sessionsLoaded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                if showingSessionDetail, let session = selectedSession {
                    SessionDetailView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if isLoadingSessions {
                    VStack {
                        Spacer()
                        ProgressView("Loading sessions...")
                        Spacer()
                    }
                } else if !sessionsLoaded {
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Select Sessions tab to view your sessions")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else if filteredSessions.isEmpty {
                    EmptySessionsStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Personalized greeting section
                            VStack(alignment: .leading, spacing: 8) {
                                Text(personalizedGreeting)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 120)
                                    .padding(.vertical, 16)
                                    .background(Color.gray.opacity(0.1))
                                    .padding(.bottom, 8)
                            }
                            .padding(.horizontal, 0)
                            
                            ForEach(groupedFilteredSessionDates(), id: \.self) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Date header
                                    HStack {
                                        Text(sectionTitle(for: day))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 152)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)
                                    
                                    // Sessions for this day
                                    ForEach(filteredSessions(on: day), id: \.id) { s in
                                        Button(action: { openSession(s) }) {
                                            SessionRowContent(session: s)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 120)
                                    }
                                }
                            }

                            // Infinite scroll trigger & footer
                            if transcriptStore.canLoadMoreSessions {
                                VStack {
                                    ProgressView().scaleEffect(0.9)
                                        .padding(.vertical, 16)
                                        .onAppear {
                                            transcriptStore.loadMoreSessions()
                                        }
                                }
                            } else {
                                // Optional: end of list indicator for long histories
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingSessionDetail)
        }
        .id(refreshTrigger)
        .onAppear {
            // When returning to this tab, don't get stuck loading if we already have data
            filteredSessions = onlyCompleted(transcriptStore.sessions)
            if transcriptStore.sessions.isEmpty {
                isLoadingSessions = true
                sessionsLoaded = false
                transcriptStore.refreshSessions()
            } else {
                isLoadingSessions = false
                sessionsLoaded = true
            }
        }
        // Keep filtered list in sync with store updates and auto-open latest once
        .onChange(of: transcriptStore.sessions) { newSessions in
            filteredSessions = onlyCompleted(newSessions)
            isLoadingSessions = false
            sessionsLoaded = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshContent"))) { _ in
            isLoadingSessions = true
            sessionsLoaded = false
            transcriptStore.refreshSessions()
            filteredSessions = onlyCompleted(transcriptStore.sessions)
            print("🔄 Refreshed sessions via refresh button")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SessionsRefreshed"))) { _ in
            // End loading regardless of success/failure and reapply filters
            isLoadingSessions = false
            sessionsLoaded = true
            filteredSessions = onlyCompleted(transcriptStore.sessions)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformSearch"))) { notification in
            if let searchQuery = notification.object as? String {
                performSearch(query: searchQuery)
            } else {
                // Ignore empty trigger; real text comes from SearchFieldChanged in older flow
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearSearch"))) { _ in
            filteredSessions = onlyCompleted(transcriptStore.sessions)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoBack"))) { _ in
            if showingSessionDetail {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showingSessionDetail = false
                    selectedSession = nil
                    // Update section title back to "Sessions"
                    MainWindow.shared.updateSectionTitle("Sessions")
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func openSession(_ s: ListenSession) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedSession = s
            showingSessionDetail = true
            // Update window title to "Session Details"
            MainWindow.shared.updateTitle("Session Details")
        }
    }
    
    private func groupedFilteredSessionDates() -> [Date] {
        let calendar = Calendar.current
        let sessions = filteredSessions.sorted { $0.startTime > $1.startTime }
        let groups = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }
        return groups.keys.sorted(by: >)
    }
    
    private func filteredSessions(on day: Date) -> [ListenSession] {
        let calendar = Calendar.current
        return filteredSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            .sorted { $0.startTime > $1.startTime }
    }
    
    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func performSearch(query: String) {
        // Only show complete sessions (sessions with generated notes)
        // For backward compatibility, treat sessions without isComplete field as complete
        let completeSessions = onlyCompleted(transcriptStore.sessions)
        
        if query.isEmpty {
            filteredSessions = completeSessions
        } else {
            filteredSessions = completeSessions.filter { session in
                session.fullTranscript.localizedCaseInsensitiveContains(query) ||
                (session.summary?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }

    private func onlyCompleted(_ sessions: [ListenSession]) -> [ListenSession] {
        return sessions.filter { s in
            // Show only when notes exist or explicit flag isComplete == true
            if (s.isComplete == true) { return true }
            // Fallback heuristic: require non-empty summary
            return (s.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }
    }
    
    private var personalizedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        
        switch hour {
        case 5..<12:
            greeting = "Good morning"
        case 12..<17:
            greeting = "Good afternoon"
        case 17..<22:
            greeting = "Good evening"
        default:
            greeting = "Good evening"
        }
        
        // Simple greeting without user info (API key auth)
        return "\(greeting)."
    }
}

// MARK: - Supporting Views

struct SavedSessionRowView: View {
    let session: ListenSession
    
    @State private var isExpanded: Bool = false
    
    private var durationText: String {
        guard let duration = session.duration else { return "Active" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Session info
                HStack(spacing: 8) {
                    WaveformView(isActive: false)
                        .frame(width: 10, height: 6)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listen Session")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("ID: \(session.id.prefix(8))...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Duration and timestamp
                VStack(alignment: .trailing, spacing: 2) {
                    Text(durationText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    Text(session.startTime, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Expand/collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            
            // Content preview or full text
            VStack(alignment: .leading, spacing: 8) {
                // Show summary if available
                if let summary = session.summary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summary:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(summary)
                            .font(.body)
                            .fontWeight(.medium)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                if isExpanded {
                    // Full transcript
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full Transcript:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(session.fullTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else if session.summary == nil {
                    // Preview when no summary
                    Text(session.fullTranscript)
                        .font(.body)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                
                // Stats
                HStack {
                    Text("\(session.segments.count) segments")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if session.endTime != nil {
                        Text("• Completed")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Text("• In Progress")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
            }
            
            if isExpanded && session.segments.count > 1 {
                // Show individual segments timeline
                VStack(alignment: .leading, spacing: 4) {
                    Text("Timeline:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(session.segments, id: \.id) { segment in
                        HStack {
                            Text("•")
                                .foregroundColor(.green)
                            Text(segment.text)
                                .font(.caption)
                                .textSelection(.enabled)
                            Spacer()
                            Text(segment.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct EmptySessionsStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No sessions yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("Use the Listen feature to create audio transcripts!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 300)
    }
}

#Preview {
    SessionsView()
}
