import SwiftUI

struct CreateDatasetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var datasetManager = DatasetManager.shared
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory: DatasetCategory = .custom
    @State private var content = ""
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Dataset")
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
                        
                        TextField("e.g., Sales Product Catalog", text: $name)
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
                        
                        TextField("Brief description of this dataset", text: $description)
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
                        
                        Text("Add the information you want Luca to know. This could be product details, pricing, FAQs, company policies, etc.")
                            .font(.system(size: 12))
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
                
                Button(action: createDataset) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Create")
                    }
                }
                .disabled(name.isEmpty || content.isEmpty || isCreating)
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
    }
    
    private func createDataset() {
        isCreating = true
        
        Task {
            let datasetId = await datasetManager.createDataset(
                name: name,
                description: description,
                category: selectedCategory,
                content: content
            )
            
            isCreating = false
            
            if datasetId != nil {
                dismiss()
            }
        }
    }
}

