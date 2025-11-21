import SwiftUI

struct EditDatasetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var datasetManager = DatasetManager.shared
    
    let dataset: CustomDataset
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory: DatasetCategory = .custom
    @State private var content = ""
    @State private var isUpdating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Dataset")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dataset Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        TextField("Dataset name", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Category
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(DatasetCategory.allCases, id: \.self) { category in
                                CategoryButton(
                                    category: category,
                                    isSelected: selectedCategory == category,
                                    action: { selectedCategory = category }
                                )
                            }
                        }
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        TextField("Description", text: $description)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knowledge Content")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $content)
                            .font(.system(size: 13))
                            .frame(minHeight: 200)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: updateDataset) {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Save Changes")
                    }
                }
                .disabled(name.isEmpty || content.isEmpty || isUpdating)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(name.isEmpty || content.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(8)
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            name = dataset.name
            description = dataset.description
            selectedCategory = dataset.category
            content = dataset.content
        }
    }
    
    private func updateDataset() {
        isUpdating = true
        
        Task {
            guard let datasetId = dataset.id else { return }
            let success = await datasetManager.updateDataset(
                id: datasetId,
                name: name,
                description: description,
                category: selectedCategory,
                content: content
            )
            
            isUpdating = false
            
            if success {
                dismiss()
            }
        }
    }
}

