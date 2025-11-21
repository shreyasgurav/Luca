const fetch = require('node-fetch');

// Read environment variables dynamically instead of at module load time
function getOpenAIConfig() {
  const DEFAULT_MODEL = 'gpt-4o-mini';
  const allowedModels = new Set([
    'gpt-4o-mini',
    'gpt-4o',
    'gpt-4.1-mini',
    'gpt-4.1'
  ]);
  const envModel = (process.env.OPENAI_MODEL || '').trim();
  const model = allowedModels.has(envModel) ? envModel : DEFAULT_MODEL;
  return {
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    OPENAI_BASE: process.env.OPENAI_BASE || 'https://api.openai.com/v1',
    OPENAI_MODEL: model
  };
}

// Luca's system prompt — SOLUTION-FIRST assistant
const LUCA_SYSTEM_PROMPT = `You are Luca, a SOLUTION-FIRST AI assistant. Your primary goal is to SOLVE problems, not just explain them.

CORE PRINCIPLES:
1. SOLUTION FIRST: Always lead with the fix/action/answer
2. Brief explanation ONLY if needed for context
3. Be direct, actionable, and practical
4. No unnecessary explanations unless specifically asked

RESPONSE FORMAT:
- Give direct, actionable responses
- No prefixes like "SOLUTION:" or special formatting
- Just provide the answer or action needed

CAPABILITIES:
- Screen: Auto-captures screenshots when you reference "on my screen", errors, UI elements
- Audio: Uses transcripts from recent calls/meetings when you mention them  
- Places: Finds nearby locations when you ask for "near me", "open now", etc.
- Memory: Stores preferences and important facts you tell me

EXAMPLES:

❌ Wrong: "This error occurs because of a network timeout. Network timeouts happen when..."
✅ Right: "Run: curl -I [url] to test connection. If it fails, restart your router."

❌ Wrong: "Docker is a containerization platform that allows..."  
✅ Right: "Run: docker run -d -p 80:80 nginx. This starts an nginx server on port 80."

❌ Wrong: "This React error is caused by state mutations..."
✅ Right: "Add key prop: <Component key={item.id} />. React needs unique keys for list items."

❌ Wrong: "CSS flexbox is a layout method that..."
✅ Right: "Add: display: flex; justify-content: center; align-items: center;"

WHEN TO EXPLAIN MORE:
- Only if user asks "why?" or "how does this work?"
- Only if context is critical for the solution to work
- Keep explanations under 2 sentences

Be the assistant that gets things done, not the one that talks about doing things.`;

async function callOpenAI({ imageUrl, promptContext, includeOCR, sessionId }) {
  const { OPENAI_API_KEY, OPENAI_BASE, OPENAI_MODEL } = getOpenAIConfig();
  
  // Build messages array with system prompt
  const messages = [
    {
      role: 'system',
      content: LUCA_SYSTEM_PROMPT
    }
  ];

  // Add user message with content
  const userMessage = {
    role: 'user',
    content: imageUrl ? [
      { type: 'text', text: promptContext || 'Please analyze this screenshot and help me.' },
      { type: 'image_url', image_url: { url: imageUrl } }
    ] : [{ type: 'text', text: promptContext || 'Hello Luca!' }]
  };
  
  messages.push(userMessage);
  
  // GPT-4o-mini uses standard Chat Completions format with vision support
  const payload = {
    model: OPENAI_MODEL,
    messages: messages,
    max_tokens: 4000,
    temperature: 0.7  // Add some personality while keeping responses focused
  };

  // GPT-4o-mini is much faster, but set reasonable timeout for complex images
  const timeoutMs = 60000; // 60 seconds
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
      throw new Error('OpenAI request timed out after 60 seconds');
    }
    throw error;
  }
}

module.exports = { callOpenAI, getOpenAIConfig };


