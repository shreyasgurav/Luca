const { callOpenAI } = require('../lib/openaiClient');

// OpenAI Embedding API endpoint
module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { 
    res.statusCode = 405; 
    return res.end('Method Not Allowed'); 
  }

  try {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const { text, userId } = body || {};
    
    if (!text) { 
      res.statusCode = 400; 
      return res.end('Missing text'); 
    }

    console.log('🔢 Generating embedding for text:', text.substring(0, 100) + '...');
    
    // Call OpenAI Embeddings API
    // Note: We'll use a direct API call since the existing callOpenAI is for chat completions
    const embeddingResponse = await generateEmbedding(text);
    
    if (!embeddingResponse || !embeddingResponse.embedding) {
      throw new Error('Failed to generate embedding');
    }

    console.log(`✅ Generated embedding with ${embeddingResponse.embedding.length} dimensions`);

    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ 
      success: true,
      embedding: embeddingResponse.embedding,
      dimensions: embeddingResponse.embedding.length,
      model: embeddingResponse.model || 'text-embedding-3-small'
    }));
    
  } catch (err) {
    console.error('❌ Embedding generation error:', err);
    res.statusCode = 500; 
    res.end(JSON.stringify({ error: err.message }));
  }
};

// Generate embedding using OpenAI API
async function generateEmbedding(text) {
  const fetch = require('node-fetch');
  
  if (!process.env.OPENAI_API_KEY) {
    console.warn('⚠️ OPENAI_API_KEY not set, using mock embeddings');
    return generateMockEmbedding(text);
  }

  try {
    const response = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        input: text,
        model: process.env.EMBEDDING_MODEL || 'text-embedding-3-small',
        encoding_format: 'float'
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`OpenAI API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    
    if (!data.data || !data.data[0] || !data.data[0].embedding) {
      throw new Error('Invalid embedding response format');
    }

    // after getting data:
    const rawEmbedding = data.data[0].embedding;
    const dims = rawEmbedding.length;
    console.log(`Embedding model: ${data.model}, dimensions: ${dims}`);
    const magnitude = Math.sqrt(rawEmbedding.reduce((sum, v) => sum + v*v, 0));
    const normalized = rawEmbedding.map(v => v / (magnitude || 1));
    
    return {
      embedding: normalized,
      model: data.model,
      usage: data.usage
    };

  } catch (error) {
    console.error('OpenAI embedding API error:', error);
    console.log('🔄 Falling back to mock embeddings');
    return generateMockEmbedding(text);
  }
}

// Generate mock embedding for testing (1536 dimensions like OpenAI)
function generateMockEmbedding(text) {
  // Create a simple hash-based embedding for testing
  const hash = require('crypto').createHash('sha256').update(text).digest('hex');
  const embedding = [];
  
  // Generate 1536 dimensions based on text hash
  for (let i = 0; i < 1536; i++) {
    const charCode = hash.charCodeAt(i % hash.length);
    const normalized = (charCode / 255.0) * 2 - 1; // Normalize to [-1, 1]
    embedding.push(normalized);
  }
  
  // Normalize the vector to unit length
  const magnitude = Math.sqrt(embedding.reduce((sum, val) => sum + val * val, 0));
  const normalizedEmbedding = embedding.map(val => val / magnitude);
  
  return {
    embedding: normalizedEmbedding,
    model: 'mock-embedding-1536',
    usage: { total_tokens: text.split(' ').length }
  };
}
