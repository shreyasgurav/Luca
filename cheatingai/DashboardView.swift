import SwiftUI
import FirebaseAuth

struct DashboardView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var memoryManager = VectorMemoryManager.shared
    @StateObject private var sessionsStore = SessionTranscriptStore.shared
    @State private var selectedTab: DashboardTab = .memory
    @State private var memories: [VectorMemory] = []
    @State private var isLoadingMemories = true
    @State private var searchText = ""
    @State private var showingMemoryDetail = false
    @State private var selectedMemory: VectorMemory?
    @State private var showingDeleteAlert = false
    @State private var memoryToDelete: VectorMemory?
    
    enum DashboardTab: String, CaseIterable {
        case memory = "Memory"
        case profile = "Profile"
        case integrations = "Integrations"
        case sessions = "Sessions"
        
        var icon: String {
            switch self {
            case .memory: return "brain.head.profile"
            case .profile: return "person.circle"
            case .integrations: return "puzzlepiece"
            case .sessions: return "waveform"
            }
        }
        
        var logoImage: some View {
            Group {
                switch self {
                case .memory:
                    Image("NovaLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                case .profile:
                    Image(systemName: "person.circle")
                        .font(.system(size: 16))
                        .frame(width: 16, height: 16)
                case .integrations:
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 16))
                        .frame(width: 16, height: 16)
                case .sessions:
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .frame(width: 16, height: 16)
                }
            }
        }
    }
    
    var filteredMemories: [VectorMemory] {
        if searchText.isEmpty {
            return memories
        } else {
            return memories.filter { memory in
                memory.summary.localizedCaseInsensitiveContains(searchText) ||
                memory.content.localizedCaseInsensitiveContains(searchText) ||
                memory.keywords.joined().localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with tabs
            sidebarView
        } detail: {
            // Main content area
            mainContentView
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await loadMemories()
            await sessionsStore.loadSessions()
        }
        .alert("Delete Memory", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let memory = memoryToDelete {
                    Task {
                        await deleteMemory(memory)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this memory? This action cannot be undone.")
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // User info header
            userHeaderView
            
            Divider()
            
            // Navigation tabs
            navigationTabsView
            
            Spacer()
            
            // Footer actions
            footerActionsView
        }
        .frame(minWidth: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var userHeaderView: some View {
        VStack(spacing: 12) {
            // User avatar and info
            if let user = authManager.currentUser {
                VStack(spacing: 8) {
                    // Avatar
                    Circle()
                        .fill(LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(user.displayName?.first ?? user.email?.first ?? "U"))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        )
                    
                    // User details
                    VStack(spacing: 4) {
                        Text(user.displayName ?? "User")
                            .font(.headline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text(user.email ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // Fallback if no user - show Nova logo
                VStack(spacing: 8) {
                    Image("NovaLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .shadow(color: .blue.opacity(0.2), radius: 5, x: 0, y: 2)
                    
                    Text("Nova")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
    }
    
    private var navigationTabsView: some View {
        VStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    HStack {
                        tab.logoImage
                            .frame(width: 20)
                        
                        Text(tab.rawValue)
                            .font(.body)
                            .fontWeight(selectedTab == tab ? .medium : .regular)
                        
                        Spacer()
                        
                        // Badge for counts
                        if tab == .memory && !memories.isEmpty {
                            Text("\(memories.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        } else if tab == .sessions && !sessionsStore.sessions.isEmpty {
                            Text("\(sessionsStore.sessions.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var footerActionsView: some View {
        VStack(spacing: 8) {
            Divider()
            
            // Nova branding in footer
            HStack {
                Image("NovaLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .opacity(0.6)
                
                Text("Nova")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // Settings and logout
            VStack(spacing: 0) {
                Button(action: {
                    // Add settings action here if needed
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                
                Button(action: {
                    authManager.signOut()
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.bottom)
    }
    
    // MARK: - Main Content
    
    private var mainContentView: some View {
        Group {
            if authManager.isAuthenticated {
                switch selectedTab {
                case .memory:
                    memoryManagementView
                case .profile:
                    profileView
                case .integrations:
                    integrationsView
                case .sessions:
                    sessionsView
                }
            } else {
                signInView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Sign In View
    
    private var signInView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Nova branding
            VStack(spacing: 16) {
                Image("NovaLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("Nova")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your Intelligent AI Assistant")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Sign in button
            Button(action: {
                authManager.signInWithGoogle()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                    
                    Text("Sign in with Google")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .scaleEffect(authManager.isSigningIn ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: authManager.isSigningIn)
            
            if authManager.isSigningIn {
                ProgressView()
                    .scaleEffect(1.2)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Memory Management View
    
    private var memoryManagementView: some View {
        VStack(spacing: 0) {
            // Header
            memoryHeaderView
            
            // Search bar
            searchBarView
            
            // Memory list
            memoryListView
        }
    }
    
    private var memoryHeaderView: some View {
        HStack {
            HStack(spacing: 12) {
                Image("NovaLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .shadow(color: .blue.opacity(0.2), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading) {
                    Text("Memory Management")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("\(memories.count) memories stored")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if memoryManager.isProcessingMemory {
                            Text("• Processing...")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("Refresh") {
                    Task {
                        await loadMemories()
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var memoryListView: some View {
        Group {
            if isLoadingMemories {
                VStack {
                    Spacer()
                    ProgressView("Loading memories...")
                    Spacer()
                }
            } else if filteredMemories.isEmpty {
                VStack {
                    Spacer()
                    EmptyMemoryStateView(hasSearch: !searchText.isEmpty)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredMemories, id: \.id) { memory in
                        DashboardMemoryRowView(memory: memory) {
                            selectedMemory = memory
                            showingMemoryDetail = true
                        } onDelete: {
                            memoryToDelete = memory
                            showingDeleteAlert = true
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Profile View
    
    private var profileView: some View {
        VStack(spacing: 24) {
            // Profile header
            profileHeaderView
            
            // Profile details
            profileDetailsView
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sessions View
    private var sessionsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Sessions")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Refresh") { Task { await sessionsStore.loadSessions() } }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            if sessionsStore.sessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(sessionsStore.sessions) { s in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.id)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(s.createdAt.formatted(.dateTime.day().month().hour().minute())) • \(ByteCountFormatter.string(fromByteCount: Int64(s.sizeBytes), countStyle: .file))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(s.preview)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            Spacer()
                            Button("Open in Finder") { sessionsStore.revealInFinder(s) }
                            Button("Delete") { sessionsStore.delete(s) }
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var profileHeaderView: some View {
        VStack(spacing: 16) {
            // Nova logo above avatar
            Image("NovaLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 2)
            
            // Large avatar
            Circle()
                .fill(LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 120, height: 120)
                .overlay(
                    Text(String(authManager.currentUser?.displayName?.first ?? authManager.currentUser?.email?.first ?? "U"))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(spacing: 8) {
                Text(authManager.currentUser?.displayName ?? "User")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(authManager.currentUser?.email ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var profileDetailsView: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Account Information")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    ProfileDetailRow(label: "User ID", value: authManager.currentUser?.uid ?? "N/A")
                    ProfileDetailRow(label: "Email", value: authManager.currentUser?.email ?? "N/A")
                    ProfileDetailRow(label: "Display Name", value: authManager.currentUser?.displayName ?? "Not set")
                    ProfileDetailRow(label: "Email Verified", value: authManager.currentUser?.isEmailVerified == true ? "Yes" : "No")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Memory Statistics")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    ProfileDetailRow(label: "Total Memories", value: "\(memories.count)")
                    ProfileDetailRow(label: "High Importance", value: "\(memories.filter { $0.importance >= 0.8 }.count)")
                    ProfileDetailRow(label: "Recent (7 days)", value: "\(memories.filter { $0.createdAt >= Date().addingTimeInterval(-7 * 24 * 60 * 60) }.count)")
                    ProfileDetailRow(label: "Most Common Type", value: mostCommonMemoryType())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 500)
    }

    private var integrationsView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Integrations")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 4)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gmail Integration")
                        .font(.headline)
                        .fontWeight(.medium)
                    GmailIntegrationView()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Helper Functions
    
    private func loadMemories() async {
        isLoadingMemories = true
        print("📱 Dashboard: Loading memories...")
        
        // Check authentication
        guard authManager.isAuthenticated else {
            print("❌ Dashboard: User not authenticated")
            isLoadingMemories = false
            return
        }
        
        // Debug: Print current user ID
        if let currentUser = authManager.currentUser {
            print("📱 Dashboard: Current user ID: \(currentUser.uid)")
            print("📱 Dashboard: User email: \(currentUser.email ?? "No email")")
        } else {
            print("❌ Dashboard: No current user found despite being authenticated")
        }
        
        memories = await memoryManager.getAllVectorMemories()
        print("📱 Dashboard: Loaded \(memories.count) memories")
        
        // Debug: Call the debug function to inspect what's actually in Firebase
        await memoryManager.debugListMemories()
        
        // Add some test memories if none exist (for testing)
        if memories.isEmpty {
            print("📱 Dashboard: No memories found, this is expected for new users")
        }
        
        isLoadingMemories = false
    }
    
    private func deleteMemory(_ memory: VectorMemory) async {
        await memoryManager.deleteVectorMemory(memoryId: memory.id)
        memories.removeAll { $0.id == memory.id }
    }
    

    
    private func mostCommonMemoryType() -> String {
        let typeCounts = Dictionary(grouping: memories, by: { $0.type })
            .mapValues { $0.count }
        
        let maxType = typeCounts.max { $0.value < $1.value }
        return maxType?.key.rawValue.capitalized ?? "None"
    }
}

// MARK: - Supporting Views

struct DashboardMemoryRowView: View {
    let memory: VectorMemory
    let onTap: () -> Void
    let onDelete: () -> Void
    
    private var typeColor: Color {
        switch memory.type {
        case .personal: return .purple
        case .preference: return .blue
        case .professional: return .green
        case .goal: return .orange
        case .instruction: return .red
        case .knowledge: return .cyan
        case .relationship: return .pink
        case .event: return .yellow
        }
    }
    
    private var importanceColor: Color {
        switch memory.importance {
        case 0.8...1.0: return .red
        case 0.6..<0.8: return .orange
        case 0.4..<0.6: return .yellow
        default: return .green
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    // Type badge
                    Text(memory.type.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(typeColor.opacity(0.2))
                        .foregroundColor(typeColor)
                        .clipShape(Capsule())
                    
                    // Source
                    Text(memory.source.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Importance indicator
                    Circle()
                        .fill(importanceColor)
                        .frame(width: 8, height: 8)
                    
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(memory.summary)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if memory.content != memory.summary && memory.content.count > memory.summary.count {
                        Text(memory.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                // Keywords
                if !memory.keywords.isEmpty {
                    HStack {
                        ForEach(memory.keywords.prefix(3), id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                        
                        if memory.keywords.count > 3 {
                            Text("+\(memory.keywords.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Footer
                HStack {
                    Text(memory.createdAt.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if memory.accessCount > 0 {
                        Text("• \(memory.accessCount) views")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Importance: \(String(format: "%.1f", memory.importance))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyMemoryStateView: View {
    let hasSearch: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearch ? "magnifyingglass" : "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text(hasSearch ? "No matching memories" : "No memories yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(hasSearch ? "Try a different search term" : "Start chatting to build your memory!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 300)
    }
}

struct ProfileDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Dashboard Window

class DashboardWindow {
    static let shared = DashboardWindow()
    private var window: NSWindow?
    
    private init() {}
    
    func show() {
        if window == nil {
            createWindow()
        }
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    private func createWindow() {
        let dashboardView = DashboardView()
        let hostingController = NSHostingController(rootView: dashboardView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window?.title = "Nova Dashboard"
        window?.contentViewController = hostingController
        window?.isReleasedWhenClosed = false
        window?.center()
        
        // Set minimum size
        window?.minSize = NSSize(width: 900, height: 600)
    }
}

#Preview {
    DashboardView()
}
