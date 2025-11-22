import Foundation

@MainActor
class DatasetManager: ObservableObject {
    static let shared = DatasetManager()
    
    // Firestore removed - DatasetManager is deprecated
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
        APIKeyManager.shared.localUserId
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
        // Firestore removed - DatasetManager is deprecated
        isLoading = true
        defer { isLoading = false }
        datasets = []
        print("⚠️ DatasetManager is deprecated - Firestore removed")
    }
    
    func createDataset(name: String, description: String, category: DatasetCategory, content: String) async -> String? {
        // Firestore removed - DatasetManager is deprecated
        print("⚠️ DatasetManager is deprecated - Firestore removed")
        return nil
    }
    
    func updateDataset(id: String, name: String, description: String, category: DatasetCategory, content: String) async -> Bool {
        // Firestore removed - DatasetManager is deprecated
        print("⚠️ DatasetManager is deprecated - Firestore removed")
        return false
    }
    
    func deleteDataset(id: String) async -> Bool {
        // Firestore removed - DatasetManager is deprecated
        print("⚠️ DatasetManager is deprecated - Firestore removed")
        return false
    }
    
    private func updateLastUsedDate(datasetId: String) async {
        // Firestore removed - DatasetManager is deprecated
        print("⚠️ DatasetManager is deprecated - Firestore removed")
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

