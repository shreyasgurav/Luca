import SwiftUI

struct MemoryView: View {
    @StateObject private var memoryManager = VectorMemoryManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    
    @State private var memories: [VectorMemory] = []
    @State private var isLoadingMemories = false
    @State private var memoriesLoaded = false
    @State private var showingMemoryDetail = false
    @State private var selectedMemory: VectorMemory?
    @State private var showingDeleteAlert = false
    @State private var memoryToDelete: VectorMemory?
    @State private var filteredMemories: [VectorMemory] = []
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            // Memory list
            memoryListView
        }
        .onAppear {
            Task {
                await loadMemories()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshContent"))) { _ in
            Task {
                await loadMemories()
            }
            print("🔄 Refreshed memories via refresh button")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformSearch"))) { notification in
            if let searchQuery = notification.object as? String {
                performSearch(query: searchQuery)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearSearch"))) { _ in
            filteredMemories = memories
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
    
    private var memoryListView: some View {
        Group {
            if isLoadingMemories {
                VStack {
                    Spacer()
                    ProgressView("Loading memories...")
                    Spacer()
                }
            } else if !memoriesLoaded {
                // Show state before memories are loaded
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Select Memory tab to view your memories")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else if filteredMemories.isEmpty {
                VStack {
                    Spacer()
                    EmptyMemoryStateView()
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMemories, id: \.id) { memory in
                            DashboardMemoryRowView(memory: memory) {
                                selectedMemory = memory
                                showingMemoryDetail = true
                            } onDelete: {
                                memoryToDelete = memory
                                showingDeleteAlert = true
                            }
                        }
                    }
                    .padding(.horizontal, 120)
                    .padding(.top, 20)
                }
            }
        }
        .id(refreshTrigger) // This will refresh the view when refreshTrigger changes
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
        
        // Debug: Print authentication status
        if authManager.isAuthenticated {
            print("📱 Dashboard: User authenticated with API keys")
        } else {
            print("❌ Dashboard: No authentication")
        }
        
        memories = await memoryManager.getAllVectorMemories()
        print("📱 Dashboard: Loaded \(memories.count) memories")
        
        // Debug: Call the debug function to inspect what's actually in Firebase
        await memoryManager.debugListMemories()
        
        // Add some test memories if none exist (for testing)
        if memories.isEmpty {
            print("📱 Dashboard: No memories found, this is expected for new users")
        }
        
        memoriesLoaded = true // Mark as loaded
        isLoadingMemories = false
        
        // Initialize filtered memories
        filteredMemories = memories
    }
    
    private func performSearch(query: String) {
        if query.isEmpty {
            filteredMemories = memories
        } else {
            filteredMemories = memories.filter { memory in
                memory.summary.localizedCaseInsensitiveContains(query) ||
                memory.content.localizedCaseInsensitiveContains(query)
            }
        }
    }
    
    private func deleteMemory(_ memory: VectorMemory) async {
        await memoryManager.deleteVectorMemory(memoryId: memory.id)
        memories.removeAll { $0.id == memory.id }
        filteredMemories.removeAll { $0.id == memory.id }
    }
}

// MARK: - Supporting Views

struct DashboardMemoryRowView: View {
    let memory: VectorMemory
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var showDelete = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Memory title only
                    Text(memory.summary)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right: Date/Time OR Delete button on hover
            ZStack(alignment: .trailing) {
                Text(memory.createdAt.formatted(.dateTime.day().month().hour().minute()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    .opacity(showDelete ? 0 : 1)
                    .animation(.easeInOut(duration: 0.12), value: showDelete)
                
                Button(action: onDelete) {
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
        .onTapGesture {
            onTap()
        }
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
        .contentShape(Rectangle())
    }
}

struct EmptyMemoryStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No memories yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("Start chatting to build your memory!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 300)
    }
}

#Preview {
    MemoryView()
}
