// Luca AI API Functions
// This file serves as the main entry point for the API directory

module.exports = {
  analyze: require('./analyze'),
  chat: require('./chat'),
  embedding: require('./embedding'),
  memory: require('./memory'),
  places: require('./places')
};

// Simple test endpoint
if (require.main === module) {
  console.log('🚀 Luca AI API Functions loaded successfully!');
  console.log('📁 Available functions:');
  console.log('   - /api/analyze - Screenshot analysis');
  console.log('   - /api/chat - Chat functionality');
  console.log('   - /api/embedding - Text embeddings');
  console.log('   - /api/memory - Memory operations');
  console.log('   - /api/places - Location services');
}
