import SwiftUI
import FirebaseFirestore

struct MemoryManagementView: View {
    @StateObject private var memoryManager = VectorMemoryManager.shared
    @State private var memories: [VectorMemory] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedMemory: VectorMemory?
    @State private var showingDeleteAlert = false
    @State private var showingClearAllAlert = false
    
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
        NavigationView {
            VStack {
                // Header with stats
                HStack {
                    VStack(alignment: .leading) {
                        Text("Memory Manager")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(memories.count) memories stored")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Clear All button
                    Button("Clear All") {
                        showingClearAllAlert = true
                    }
                    .foregroundColor(.red)
                    .disabled(memories.isEmpty)
                }
                .padding()
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search memories...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                // Memory list
                if isLoading {
                    Spacer()
                    ProgressView("Loading memories...")
                    Spacer()
                } else if filteredMemories.isEmpty {
                    Spacer()
                    VStack {
                        Image(systemName: "brain")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No memories yet" : "No matching memories")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "Start chatting to build your memory!" : "Try a different search term")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredMemories, id: \.id) { memory in
                            MemoryRowView(memory: memory) {
                                selectedMemory = memory
                                showingDeleteAlert = true
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .refreshable {
                await loadMemories()
            }
            .task {
                await loadMemories()
            }
            .alert("Delete Memory", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let memory = selectedMemory {
                        Task {
                            await deleteMemory(memory)
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this memory? This action cannot be undone.")
            }
            .alert("Clear All Memories", isPresented: $showingClearAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task {
                        await clearAllMemories()
                    }
                }
            } message: {
                Text("Are you sure you want to delete ALL memories? This action cannot be undone.")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func loadMemories() async {
        isLoading = true
        memories = await memoryManager.getAllVectorMemories()
        isLoading = false
    }
    
    private func deleteMemory(_ memory: VectorMemory) async {
        await memoryManager.deleteVectorMemory(memoryId: memory.id)
        memories.removeAll { $0.id == memory.id }
    }
    
    private func clearAllMemories() async {
        // Clear all vector memories
        for memory in memories {
            await memoryManager.deleteVectorMemory(memoryId: memory.id)
        }
        memories.removeAll()
    }
}

struct MemoryRowView: View {
    let memory: VectorMemory
    let onDelete: () -> Void
    
    private var importanceColor: Color {
        switch memory.importance {
        case 0.8...1.0:
            return .red
        case 0.6..<0.8:
            return .orange
        case 0.4..<0.6:
            return .yellow
        default:
            return .green
        }
    }
    
    private var sourceIcon: String {
        switch memory.source {
        case .screenshot:
            return "camera"
        case .conversation:
            return "message"
        case .explicit:
            return "hand.raised"
        case .inferred:
            return "doc.text.magnifyingglass"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with source and importance
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: sourceIcon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(memory.source.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Importance indicator
                Circle()
                    .fill(importanceColor)
                    .frame(width: 8, height: 8)
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
            
            // Summary
            Text(memory.summary)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(3)
            
            // Full content (if different from summary)
            if memory.content != memory.summary && memory.content.count > memory.summary.count {
                Text(memory.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Keywords
            if !memory.keywords.isEmpty {
                HStack {
                    ForEach(memory.keywords, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
            }
            
            // Footer with dates
            HStack {
                Text("Created: \(memory.createdAt.formatted(.dateTime.day().month().hour().minute()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if memory.lastAccessedAt != memory.createdAt {
                    Text("Last accessed: \(memory.lastAccessedAt.formatted(.dateTime.day().month().hour().minute()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Memory Management Window

class MemoryManagementWindow {
    static let shared = MemoryManagementWindow()
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
        let memoryView = MemoryManagementView()
        let hostingController = NSHostingController(rootView: memoryView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window?.title = "Memory Manager - Nova"
        window?.contentViewController = hostingController
        window?.isReleasedWhenClosed = false
        window?.center()
        
        // Set minimum size
        window?.minSize = NSSize(width: 600, height: 400)
    }
}

#Preview {
    MemoryManagementView()
}
