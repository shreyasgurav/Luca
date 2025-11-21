import Foundation
import FirebaseFirestore

// MARK: - Dataset Models

struct CustomDataset: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var name: String
    var description: String
    var category: DatasetCategory
    var content: String // Combined text content from all sources
    var embedding: [Double]? // Vector embedding for semantic search
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    
    var displayName: String {
        return name.isEmpty ? "Untitled Dataset" : name
    }
}

enum DatasetCategory: String, Codable, CaseIterable {
    case sales = "Sales"
    case interview = "Interview"
    case meeting = "Meeting"
    case presentation = "Presentation"
    case support = "Support"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .sales: return "dollarsign.circle.fill"
        case .interview: return "person.2.fill"
        case .meeting: return "video.fill"
        case .presentation: return "doc.richtext.fill"
        case .support: return "headphones"
        case .custom: return "folder.fill"
        }
    }
    
    var color: String {
        switch self {
        case .sales: return "green"
        case .interview: return "blue"
        case .meeting: return "purple"
        case .presentation: return "orange"
        case .support: return "pink"
        case .custom: return "gray"
        }
    }
}

// MARK: - Dataset Entry (for building datasets)

struct DatasetEntry: Codable, Identifiable {
    let id: String
    let datasetId: String
    let title: String
    let content: String
    let source: DatasetSource
    let createdAt: Date
}

enum DatasetSource: String, Codable {
    case manual = "Manual Entry"
    case file = "File Upload"
    case text = "Text Input"
}

