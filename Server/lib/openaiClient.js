const fetch = require('node-fetch');

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENAI_BASE = process.env.OPENAI_BASE || 'https://api.openai.com/v1';

async function callOpenAI({ imageUrl, promptContext, includeOCR, sessionId }) {
  const content = [{ type: 'input_text', text: promptContext || 'Please analyze this screenshot and answer the user.' }];
  if (imageUrl) {
    // Use image_url for both https and data URLs
    content.push({ type: 'input_image', image_url: imageUrl });
  }
  // Use GPT-4o-mini for best cost/performance ratio
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  
  // GPT-4o-mini uses standard Chat Completions format with vision support
  const payload = {
    model: model,
    messages: [{ 
      role: 'user', 
      content: imageUrl ? [
        { type: 'text', text: promptContext || 'Please analyze this screenshot and answer the user.' },
        { type: 'image_url', image_url: { url: imageUrl } }
      ] : [{ type: 'text', text: promptContext || 'Please answer the user.' }]
    }],
    max_completion_tokens: 4000
  };

  // GPT-4o-mini is much faster, but set reasonable timeout for complex images
  const timeoutMs = 60000; // 1 minute
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  // GPT-4o-mini uses standard Chat Completions endpoint
  try {
    const res = await fetch(`${OPENAI_BASE}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload),
      signal: controller.signal
    });
    clearTimeout(timeoutId);
    
    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`OpenAI error ${res.status}: ${errText}`);
    }
    return await res.json();
  } catch (error) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error('OpenAI request timed out after 3 minutes');
    }
    throw error;
  }
}

module.exports = { callOpenAI };


