# 🧠 Vector Memory System - Advanced AI Context Management

## Overview

This is a production-ready vector-based memory system inspired by ChatGPT and Claude, implementing state-of-the-art semantic search and context management for AI conversations.

## 🎯 Key Features

### **Semantic Memory Storage**
- **Vector Embeddings**: Uses OpenAI's `text-embedding-3-small` for efficient semantic representation
- **8 Memory Types**: Personal, Preference, Professional, Goal, Instruction, Knowledge, Relationship, Event
- **Smart Categorization**: Automatic classification using pattern recognition
- **Importance Scoring**: 0.0-1.0 scoring with automatic adjustment over time
- **Confidence Tracking**: AI confidence levels for each memory

### **Advanced Retrieval System**
- **Cosine Similarity Search**: Finds semantically similar memories
- **Hybrid Scoring**: Combines semantic similarity + importance + recency + access frequency
- **Context Window Management**: Respects token limits while maximizing relevance
- **Memory Decay**: Automatic importance reduction for old, unused memories
- **Fallback Search**: Keyword-based backup when vector search fails

### **Intelligent Context Building**
- **Hierarchical Context**: User profile → Relevant memories → Recent conversation
- **Token Budgeting**: Smart allocation across different context types
- **Real-time Adaptation**: Updates memory access patterns during conversations
- **Deduplication**: Prevents storing similar information multiple times

## 🏗️ Architecture

### **Data Flow**
1. **User Input** → Pattern analysis for memory extraction
2. **Memory Creation** → Generate embeddings → Store in Firestore
3. **Query Processing** → Generate query embedding → Semantic search
4. **Context Assembly** → Rank results → Build context → Inject into prompt
5. **Response Generation** → Update access patterns → Extract new memories

### **Storage Structure**
```
Firestore Collections:
├── vector_memories/          # Main semantic memories
├── messages/                 # Conversation logs
├── sessions/                 # Chat sessions with summaries
└── users/                    # User profiles and preferences
```

### **Vector Memory Schema**
```swift
struct VectorMemory {
    let id: String
    let userId: String
    let type: MemoryType           // 8 categories
    let content: String            // Full memory text
    let summary: String            // Brief description
    let keywords: [String]         // Extracted keywords
    let embedding: [Double]        // 1536-dim vector
    let importance: Double         // 0.0-1.0 score
    let confidence: Double         // AI confidence
    let source: MemorySource       // How it was created
    let context: MemoryContext     // Session/conversation info
    let createdAt: Date
    let lastAccessedAt: Date
    let accessCount: Int           // Usage frequency
    let decayFactor: Double        // Time-based importance decay
    let isActive: Bool             // Whether to use in retrieval
}
```

## 🔧 Technical Implementation

### **Embedding Generation**
- **Model**: `text-embedding-3-small` (1536 dimensions)
- **Caching**: NSCache for recent embeddings
- **Cost Optimization**: Smart caching and batching
- **Fallback**: Keyword-based search if embeddings fail

### **Semantic Search Algorithm**
1. **Generate Query Embedding** using OpenAI API
2. **Fetch User Memories** from Firestore (filtered by user + active status)
3. **Calculate Cosine Similarity** between query and memory embeddings
4. **Apply Hybrid Scoring**:
   ```
   score = semantic_similarity + 
           importance_boost + 
           recency_boost + 
           access_frequency_boost + 
           keyword_match_boost
   ```
5. **Filter by Threshold** (minimum similarity: 0.3)
6. **Sort by Final Score** and return top results

### **Context Building Strategy**
```
Context Structure:
├── User Profile (highest priority, ~300 tokens)
├── Relevant Memories (ranked by score, ~1200 tokens)
└── Recent Conversation (chronological, ~500 tokens)
```

### **Memory Extraction Patterns**
```swift
Personal Info:     "my name is", "i'm", "i live", "my birthday"
Preferences:       "i like", "i prefer", "i love", "i hate"
Goals/Projects:    "project", "goal", "working on", "deadline"
Instructions:      "remember", "always", "help me", "remind me"
Knowledge:         "important", "fact", "should know", "tell you"
```

## 🚀 Performance Optimizations

### **Caching Strategy**
- **Embedding Cache**: 100 recent embeddings in memory
- **Query Result Cache**: Recent search results
- **Session Context Cache**: Current conversation context

### **Database Optimizations**
- **Composite Indexes**: userId + isActive + importance
- **Batch Operations**: Bulk memory updates
- **Lazy Loading**: Load memories on-demand
- **Memory Decay**: Periodic cleanup of old memories

### **Cost Management**
- **Smart Embedding**: Only generate for important content
- **Batch Processing**: Group multiple requests
- **Model Selection**: Use cost-effective `text-embedding-3-small`
- **Threshold Filtering**: Skip low-similarity results

## 📊 Memory Management Features

### **Vector Memory UI**
- **Semantic Search**: Natural language queries
- **Memory Type Filtering**: Browse by category
- **Relevance Scoring**: Visual importance indicators
- **Access Analytics**: Usage frequency tracking
- **Bulk Operations**: Mass delete/export

### **Admin Controls**
- **Memory Decay Settings**: Automatic importance reduction
- **Retention Policies**: Age-based cleanup
- **Performance Metrics**: Search latency, hit rates
- **Cost Monitoring**: Embedding generation costs

## 🔒 Privacy & Security

### **Data Protection**
- **User Isolation**: Strict userId filtering
- **Firestore Rules**: Server-side access control
- **Encryption**: At-rest data encryption
- **GDPR Compliance**: Full export/delete capabilities

### **Memory Sensitivity**
- **Confidence Scoring**: Track AI accuracy
- **Source Attribution**: Know how memories were created
- **Manual Override**: User can edit/delete any memory
- **Audit Trail**: Track all memory operations

## 📈 Performance Metrics

### **Retrieval Quality**
- **Semantic Accuracy**: How well memories match queries
- **Context Relevance**: User satisfaction with injected context
- **Response Quality**: Improvement in AI responses
- **Memory Utilization**: Which memories are most useful

### **System Performance**
- **Search Latency**: Average time for semantic search
- **Embedding Generation**: Time to create vectors
- **Database Query Time**: Firestore response times
- **Memory Efficiency**: RAM usage for caching

## 🛠️ Setup Instructions

### **Server Setup**
1. **Add Environment Variables**:
   ```bash
   OPENAI_API_KEY=your_key_here
   EMBEDDING_MODEL=text-embedding-3-small
   ```

2. **Install Dependencies**:
   ```bash
   cd Server && npm install
   ```

3. **Start Server**:
   ```bash
   node server.js
   ```

### **Firebase Configuration**
1. **Enable Firestore** in Firebase Console
2. **Create Indexes**:
   ```
   Collection: vector_memories
   Fields: userId (Ascending), isActive (Ascending), importance (Descending)
   ```

3. **Security Rules**:
   ```javascript
   match /vector_memories/{memoryId} {
     allow read, write: if request.auth.uid == resource.data.userId;
   }
   ```

### **iOS App Setup**
1. **Add Dependencies**: FirebaseFirestore, FirebaseAuth
2. **Configure URL Schemes**: For OAuth redirects
3. **Build and Run**: All vector memory features included

## 🔮 Future Enhancements

### **Advanced Features**
- **Multi-modal Memories**: Image + text embeddings
- **Cross-user Insights**: Anonymized pattern learning
- **Temporal Awareness**: Time-based memory retrieval
- **Emotional Context**: Sentiment-aware memories

### **Performance Improvements**
- **Vector Database**: Dedicated solution (Pinecone, Weaviate)
- **Edge Embeddings**: Local model for privacy
- **Streaming Search**: Real-time result updates
- **Federated Learning**: Improved extraction without data sharing

## 💡 Usage Examples

### **Personal Assistant Mode**
```
User: "What time is my dentist appointment?"
System: Searches memories for "dentist" + "appointment"
Response: "Based on your calendar, your dentist appointment is at 2 PM tomorrow."
```

### **Project Tracking**
```
User: "How's my SwiftUI project going?"
System: Retrieves project-related memories
Response: "You mentioned you were working on the authentication system last week..."
```

### **Preference Learning**
```
User: "Recommend a restaurant"
System: Uses preference memories (cuisine, price, location)
Response: "Based on your love for Italian food and preference for cozy places..."
```

## 📋 API Endpoints

### **Memory Management**
- `POST /api/embedding` - Generate text embeddings
- `POST /api/memory/extract` - Extract facts from content
- `GET /api/memory/search` - Semantic memory search
- `DELETE /api/memory/{id}` - Delete specific memory

### **Analytics**
- `GET /api/memory/stats` - Usage statistics
- `GET /api/memory/performance` - System metrics
- `POST /api/memory/decay` - Trigger memory decay process

---

This vector memory system provides enterprise-grade AI memory capabilities with the same sophistication as ChatGPT and Claude, optimized for real-world deployment and user privacy.
