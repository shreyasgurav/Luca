import SwiftUI

struct CustomiseView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var datasetManager = DatasetManager.shared
    @State private var showingCreateSheet = false
    @State private var showingEditSheet = false
    @State private var selectedDataset: CustomDataset?
    
    var body: some View {
        VStack(spacing: 0) {
            if datasetManager.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading datasets...")
                    Spacer()
                }
            } else if datasetManager.datasets.isEmpty {
                emptyStateView
            } else {
                datasetsListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .sheet(isPresented: $showingCreateSheet) {
            CreateDatasetView()
        }
        .sheet(isPresented: $showingEditSheet) {
            if let dataset = selectedDataset {
                EditDatasetView(dataset: dataset)
            }
        }
        .onAppear {
            Task {
                await datasetManager.fetchDatasets()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 64))
                    .foregroundColor(.blue.opacity(0.6))
                
                Text("No Datasets Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Create your first dataset to make Luca context-aware.\nAdd product info, sales data, or any knowledge you need.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button(action: {
                    showingCreateSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Dataset")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
    
    // MARK: - Datasets List
    
    private var datasetsListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("My Datasets")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    showingCreateSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New Dataset")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
            
            // Datasets Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(datasetManager.datasets) { dataset in
                        DatasetCard(
                            dataset: dataset,
                            onEdit: {
                                selectedDataset = dataset
                                showingEditSheet = true
                            },
                            onDelete: {
                                Task {
                                    if let datasetId = dataset.id {
                                        _ = await datasetManager.deleteDataset(id: datasetId)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Dataset Card

struct DatasetCard: View {
    let dataset: CustomDataset
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: dataset.category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                Spacer()
                
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
            }
            
            // Title
            Text(dataset.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Description
            Text(dataset.description)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(height: 36)
            
            // Footer
            HStack {
                Text(dataset.category.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                
                Spacer()
                
                if let lastUsed = dataset.lastUsedAt {
                    Text(timeAgo(from: lastUsed))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .alert("Delete Dataset", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(dataset.name)\"? This action cannot be undone.")
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
