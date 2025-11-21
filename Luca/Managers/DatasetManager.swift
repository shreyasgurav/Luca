import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class DatasetManager: ObservableObject {
    static let shared = DatasetManager()
    
    private let db = Firestore.firestore()
    @Published var datasets: [CustomDataset] = []
    @Published var selectedDatasetId: String? = nil // nil = "No Dataset"
    @Published var isLoading = false
    
    private init() {
        // Load selected dataset from UserDefaults
        if let savedDatasetId = UserDefaults.standard.string(forKey: "selectedDatasetId") {
            selectedDatasetId = savedDatasetId
        }
    }
    
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    // MARK: - Selected Dataset Management
    
    func setSelectedDataset(_ datasetId: String?) {
        selectedDatasetId = datasetId
        
        // Save to UserDefaults
        if let datasetId = datasetId {
            UserDefaults.standard.set(datasetId, forKey: "selectedDatasetId")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedDatasetId")
        }
        
        // Update last used date if dataset is selected
        if let datasetId = datasetId {
            Task {
                await updateLastUsedDate(datasetId: datasetId)
            }
        }
        
        print("🎯 Selected dataset: \(datasetId ?? "None")")
    }
    
    var selectedDataset: CustomDataset? {
        guard let id = selectedDatasetId else { return nil }
        return datasets.first(where: { $0.id == id })
    }
    
    // MARK: - CRUD Operations
    
    func fetchDatasets() async {
        guard let userId = currentUserId else {
            print("❌ No user ID available")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection("custom_datasets")
                .whereField("userId", isEqualTo: userId)
                .order(by: "updatedAt", descending: true)
                .getDocuments()
            
            let fetchedDatasets = snapshot.documents.compactMap { doc -> CustomDataset? in
                try? doc.data(as: CustomDataset.self)
            }
            
            datasets = fetchedDatasets
            print("✅ Fetched \(datasets.count) datasets")
        } catch {
            print("❌ Error fetching datasets: \(error)")
        }
    }
    
    func createDataset(name: String, description: String, category: DatasetCategory, content: String) async -> String? {
        guard let userId = currentUserId else {
            print("❌ No user ID available for dataset creation")
            print("❌ Current user: \(Auth.auth().currentUser?.email ?? "nil")")
            return nil
        }
        
        print("🔄 Creating dataset for user: \(userId)")
        print("🔄 Dataset name: \(name)")
        print("🔄 Content length: \(content.count) characters")
        
        // Generate embedding for content
        guard let embedding = await generateEmbedding(for: content) else {
            print("❌ Failed to generate embedding")
            return nil
        }
        
        print("✅ Generated embedding with \(embedding.count) dimensions")
        
        let dataset = CustomDataset(
            id: UUID().uuidString,
            userId: userId,
            name: name,
            description: description,
            category: category,
            content: content,
            embedding: embedding,
            createdAt: Date(),
            updatedAt: Date(),
            lastUsedAt: nil
        )
        
        do {
            print("🔄 Saving to Firebase collection: custom_datasets")
            print("🔄 Document ID: \(dataset.id ?? "nil")")
            guard let datasetId = dataset.id else {
                print("❌ Dataset ID is nil")
                return nil
            }
            try await db.collection("custom_datasets").document(datasetId).setData(from: dataset)
            print("✅ Created dataset: \(name) with ID: \(datasetId)")
            
            // Refresh datasets
            await fetchDatasets()
            
            return datasetId
        } catch {
            print("❌ Error creating dataset: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            
            // Check for specific Firestore error types
            if let nsError = error as NSError? {
                if nsError.domain == "FIRFirestoreErrorDomain" {
                    switch nsError.code {
                    case 7: // PERMISSION_DENIED
                        print("🔒 Permission denied - check Firestore security rules")
                    case 14: // UNAVAILABLE
                        print("🌐 Network unavailable - check internet connection")
                    case 3: // INVALID_ARGUMENT
                        print("📝 Invalid argument - check dataset data structure")
                    default:
                        print("🔥 Other Firestore error (code: \(nsError.code))")
                    }
                }
            }
            
            return nil
        }
    }
    
    func updateDataset(id: String, name: String, description: String, category: DatasetCategory, content: String) async -> Bool {
        guard currentUserId != nil else { return false }
        
        // Generate new embedding for updated content
        guard let embedding = await generateEmbedding(for: content) else {
            print("❌ Failed to generate embedding")
            return false
        }
        
        let updateData: [String: Any] = [
            "name": name,
            "description": description,
            "category": category.rawValue,
            "content": content,
            "embedding": embedding,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        do {
            try await db.collection("custom_datasets").document(id).updateData(updateData)
            print("✅ Updated dataset: \(name)")
            
            // Refresh datasets
            await fetchDatasets()
            
            return true
        } catch {
            print("❌ Error updating dataset: \(error)")
            return false
        }
    }
    
    func deleteDataset(id: String) async -> Bool {
        do {
            try await db.collection("custom_datasets").document(id).delete()
            print("✅ Deleted dataset: \(id)")
            
            // If this was the selected dataset, clear selection
            if selectedDatasetId == id {
                setSelectedDataset(nil)
            }
            
            // Refresh datasets
            await fetchDatasets()
            
            return true
        } catch {
            print("❌ Error deleting dataset: \(error)")
            return false
        }
    }
    
    private func updateLastUsedDate(datasetId: String) async {
        do {
            try await db.collection("custom_datasets").document(datasetId).updateData([
                "lastUsedAt": FieldValue.serverTimestamp()
            ])
        } catch {
            print("❌ Error updating last used date: \(error)")
        }
    }
    
    // MARK: - Embedding Generation
    
    private func generateEmbedding(for text: String) async -> [Double]? {
        // Use OpenAI embeddings API
        let embeddingURL = "\(ClientAPI.shared.baseURL)/api/embedding"
        guard let url = URL(string: embeddingURL) else {
            print("❌ Invalid embedding URL: \(embeddingURL)")
            return nil
        }
        
        print("🔄 Generating embedding for text: \(text.prefix(50))...")
        print("🔄 Using URL: \(embeddingURL)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔄 Embedding API response status: \(httpResponse.statusCode)")
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let embedding = json["embedding"] as? [Double] {
                    print("✅ Generated embedding with \(embedding.count) dimensions")
                    return embedding
                } else {
                    print("❌ No embedding in response: \(json)")
                }
            } else {
                print("❌ Invalid JSON response: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
        } catch {
            print("❌ Embedding generation error: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Dataset Search
    
    func searchDatasetContent(query: String) async -> String? {
        guard let dataset = selectedDataset else {
            print("⚠️ No dataset selected")
            return nil
        }
        
        // Generate query embedding
        guard let queryEmbedding = await generateEmbedding(for: query) else {
            print("❌ Failed to generate query embedding")
            return nil
        }
        
        // Calculate cosine similarity
        guard let datasetEmbedding = dataset.embedding else {
            print("❌ Dataset embedding is nil")
            return nil
        }
        let similarity = cosineSimilarity(queryEmbedding, datasetEmbedding)
        
        print("🔍 Dataset search similarity: \(similarity)")
        
        // If similarity is high enough, return the dataset content
        if similarity > 0.5 {
            return dataset.content
        }
        
        return nil
    }
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0.0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}

