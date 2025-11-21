import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export default async function handler(req, res) {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { text } = req.body;

    if (!text || typeof text !== 'string') {
      return res.status(400).json({ error: 'Invalid text provided' });
    }

    console.log('🔢 Generating embedding for text:', text.substring(0, 100) + '...');

    // Generate embedding using OpenAI's text-embedding-3-small model
    const response = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: text,
      encoding_format: 'float'
    });

    const embedding = response.data[0].embedding;

    console.log('✅ Generated embedding with', embedding.length, 'dimensions');

    return res.status(200).json({
      success: true,
      embedding: embedding
    });
  } catch (error) {
    console.error('❌ Embedding generation error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to generate embedding',
      message: error.message
    });
  }
}

