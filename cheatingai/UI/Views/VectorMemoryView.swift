import SwiftUI

struct VectorMemoryView: View {
    @StateObject private var vectorMemoryManager = VectorMemoryManager.shared
    @State private var memories: [VectorMemory] = []
    @State private var searchResults: [MemorySearchResult] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var selectedMemoryType: MemoryType?
    @State private var showingDeleteAlert = false
    @State private var memoryToDelete: VectorMemory?
    
    var filteredMemories: [VectorMemory] {
        var filtered = memories
        
        if let selectedType = selectedMemoryType {
            filtered = filtered.filter { $0.type == selectedType }
        }
        
        if !searchText.isEmpty && searchResults.isEmpty {
            filtered = filtered.filter { memory in
                memory.summary.localizedCaseInsensitiveContains(searchText) ||
                memory.content.localizedCaseInsensitiveContains(searchText) ||
                memory.keywords.joined().localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered.sorted { $0.importance > $1.importance }
    }
    
    var displayMemories: [VectorMemory] {
        if !searchResults.isEmpty {
            return searchResults.map { $0.memory }
        }
        return filteredMemories
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Search and filters
                searchAndFilterView
                
                // Memory type statistics
                if memories.count > 0 {
                    memoryStatsView
                }
                
                // Memory list
                memoryListView
            }
            .navigationTitle("Vector Memory System")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    semanticSearchButton
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await loadMemories()
        }
        .alert("Delete Memory", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let memory = memoryToDelete {
                    Task { await deleteMemory(memory) }
                }
            }
        } message: {
            Text("Are you sure you want to delete this memory? This action cannot be undone.")
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Vector Memory System")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    Text("\(memories.count) memories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !searchResults.isEmpty {
                        Text("• \(searchResults.count) search results")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            if vectorMemoryManager.isProcessingMemory {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var searchAndFilterView: some View {
        VStack {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search memories semantically...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await performSemanticSearch() }
                    }
                
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Search") {
                        Task { await performSemanticSearch() }
                    }
                    .disabled(searchText.isEmpty)
                }
                
                if !searchResults.isEmpty {
                    Button("Clear") {
                        searchResults = []
                        searchText = ""
                    }
                }
            }
            
            // Memory type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    FilterChip(
                        title: "All",
                        isSelected: selectedMemoryType == nil,
                        count: memories.count
                    ) {
                        selectedMemoryType = nil
                    }
                    
                    ForEach(MemoryType.allCases, id: \.self) { type in
                        let count = memories.filter { $0.type == type }.count
                        if count > 0 {
                            FilterChip(
                                title: type.rawValue.capitalized,
                                isSelected: selectedMemoryType == type,
                                count: count
                            ) {
                                selectedMemoryType = type
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
    
    private var memoryStatsView: some View {
        let stats = calculateMemoryStats()
        
        return HStack {
            StatView(title: "High Importance", value: stats.highImportance, color: .red)
            StatView(title: "Recent (7d)", value: stats.recent, color: .blue)
            StatView(title: "Frequently Accessed", value: stats.frequentlyAccessed, color: .green)
            StatView(title: "Total Embeddings", value: memories.count, color: .purple)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var memoryListView: some View {
        Group {
            if isLoading {
                ProgressView("Loading vector memories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayMemories.isEmpty {
                EmptyMemoryView(hasSearch: !searchText.isEmpty)
            } else {
                List {
                    ForEach(displayMemories, id: \.id) { memory in
                        VectorMemoryRowView(
                            memory: memory,
                            searchResult: searchResults.first { $0.memory.id == memory.id }
                        ) {
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
    
    private var semanticSearchButton: some View {
        Button("Semantic Search") {
            Task { await performSemanticSearch() }
        }
        .disabled(searchText.isEmpty || isSearching)
    }
    
    // MARK: - Actions
    
    private func loadMemories() async {
        isLoading = true
        memories = await vectorMemoryManager.getAllVectorMemories()
        isLoading = false
    }
    
    private func performSemanticSearch() async {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = await vectorMemoryManager.searchMemoriesWithResults(query: searchText)
        isSearching = false
    }
    
    private func deleteMemory(_ memory: VectorMemory) async {
        await vectorMemoryManager.deleteVectorMemory(memoryId: memory.id)
        memories.removeAll { $0.id == memory.id }
        searchResults.removeAll { $0.memory.id == memory.id }
    }
    
    private func calculateMemoryStats() -> (highImportance: Int, recent: Int, frequentlyAccessed: Int) {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        return (
            highImportance: memories.filter { $0.importance >= 0.8 }.count,
            recent: memories.filter { $0.createdAt >= sevenDaysAgo }.count,
            frequentlyAccessed: memories.filter { $0.accessCount >= 3 }.count
        )
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .background(Color.secondary.opacity(0.3))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StatView: View {
    let title: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct VectorMemoryRowView: View {
    let memory: VectorMemory
    let searchResult: MemorySearchResult?
    let onDelete: () -> Void
    
    private var relevanceScore: String {
        if let result = searchResult {
            return String(format: "%.3f", result.relevanceScore)
        }
        return String(format: "%.2f", memory.importance)
    }
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Memory type badge
                Text(memory.type.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor.opacity(0.2))
                    .foregroundColor(typeColor)
                    .clipShape(Capsule())
                
                // Source indicator
                Text(memory.source.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Relevance/Importance score
                VStack(alignment: .trailing) {
                    Text(searchResult != nil ? "Relevance" : "Importance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(relevanceScore)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(searchResult != nil ? .blue : .primary)
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(memory.summary)
                    .font(.body)
                    .fontWeight(.medium)
                
                if memory.content != memory.summary {
                    Text(memory.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            
            // Keywords
            if !memory.keywords.isEmpty {
                HStack {
                    ForEach(memory.keywords.prefix(5), id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                    
                    if memory.keywords.count > 5 {
                        Text("+\(memory.keywords.count - 5)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Footer
            HStack {
                Text("Created: \(memory.createdAt.formatted(.dateTime.day().month().hour().minute()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if memory.accessCount > 0 {
                    Text("• Accessed \(memory.accessCount) times")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Confidence: \(String(format: "%.1f", memory.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Search result details
            if let result = searchResult {
                HStack {
                    Text("Semantic: \(String(format: "%.3f", result.semanticSimilarity))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    
                    Text("Importance: +\(String(format: "%.3f", result.importanceBoost))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Text("Recency: +\(String(format: "%.3f", result.recencyBoost))")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(searchResult != nil ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

struct EmptyMemoryView: View {
    let hasSearch: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearch ? "magnifyingglass" : "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(hasSearch ? "No matching memories found" : "No vector memories yet")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text(hasSearch ? "Try different search terms or semantic queries" : "Start chatting to build your semantic memory!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Extensions

extension MemoryType: CaseIterable {
    public static var allCases: [MemoryType] {
        return [.personal, .preference, .professional, .goal, .instruction, .knowledge, .relationship, .event]
    }
}

// MARK: - Vector Memory Window

class VectorMemoryWindow {
    static let shared = VectorMemoryWindow()
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
        let vectorMemoryView = VectorMemoryView()
        let hostingController = NSHostingController(rootView: vectorMemoryView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window?.title = "Vector Memory System - Nova"
        window?.contentViewController = hostingController
        window?.isReleasedWhenClosed = false
        window?.center()
        
        // Set minimum size
        window?.minSize = NSSize(width: 800, height: 600)
    }
}

#Preview {
    VectorMemoryView()
}
