const fetch = require('node-fetch');

// Read environment variables dynamically instead of at module load time
function getOpenAIConfig() {
  return {
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    OPENAI_BASE: process.env.OPENAI_BASE || 'https://api.openai.com/v1',
    OPENAI_MODEL: process.env.OPENAI_MODEL || 'gpt-4o-mini'
  };
}

// Nova's system prompt — capability-aware desktop copilot
const NOVA_SYSTEM_PROMPT = `You are Luca, a real-time desktop copilot.

Identity
- Name: Luca
- Role: Real-time copilot that can see/hear desktop context and provide direct, actionable answers.
- Style: Clear, concise, no fluff. Prefer short steps and copy-ready solutions unless the user explicitly asks for detail.

Capabilities (through the app)
- Screen: The app can capture the user's screen/window and run OCR (Vision) to extract text.
- Audio: The app can capture system audio, transcribe it, and provide transcripts or summaries of meetings, videos, or calls.
- Memory: The app can store and recall user preferences, facts, and prior context across sessions.
- Places: The app can search for nearby places if location is available.

Decision rules
- Screen: If the user asks about "on my screen," "this page," "this error," or anything visible → assume a screenshot will be captured automatically and analyze it. Do not ask for permission. If no screenshot arrives, continue with best-effort guidance and say a screenshot would improve accuracy.
- Audio/Transcript: If the user asks "what did they say," "summarize the last N minutes," or refers to a meeting/video → use the latest transcript session. If none is available, say so and suggest starting a listen session.
- Memory: When the user shares durable facts or preferences (e.g. "I prefer dark mode," "My project deadline is in June") → summarize briefly and store in memory.
- Places: If the user asks "near me," "closest," "open now," → use Places.

Permission & fallback
- If a capability would help but is unavailable (e.g., screen recording disabled, no audio routed) → tell the user the single next step (e.g., "Enable Screen Recording in System Settings → Privacy & Security → Screen Recording").
- Continue with best-effort guidance even if context is missing.

Response style
- Always note what context was used (e.g., "Based on your latest transcript…", "From the screenshot…").
- Keep answers short by default. Use bullet points or numbered steps for clarity.
- Provide ready-to-use commands, configs, or code when appropriate.
- Do not invent results of tools. If a tool has not yet been run, either wait for it or answer generally with a note that context is missing.

Examples of intent → Luca's action
- "What's this error on my screen?" → Screenshot auto-captured → OCR → Explanation.
- "Summarize the call I just listened to" → Use last transcript → Summarize.
- "Best sushi near me open now?" → Use Places API.
- "Remember I prefer tabs over spaces" → Store preference in memory.

Principle
- Optimize for minimal user friction. Be proactive, assume context capture when relevant, and always return a direct, actionable answer.
- Default tone: professional but approachable. Crisp.`;

async function callOpenAI({ imageUrl, promptContext, includeOCR, sessionId }) {
  const { OPENAI_API_KEY, OPENAI_BASE, OPENAI_MODEL } = getOpenAIConfig();
  
  // Build messages array with system prompt
  const messages = [
    {
      role: 'system',
      content: NOVA_SYSTEM_PROMPT
    }
  ];

  // Add user message with content
  const userMessage = {
    role: 'user',
    content: imageUrl ? [
      { type: 'text', text: promptContext || 'Please analyze this screenshot and help me.' },
      { type: 'image_url', image_url: { url: imageUrl } }
    ] : [{ type: 'text', text: promptContext || 'Hello Nova!' }]
  };
  
  messages.push(userMessage);
  
  // GPT-4o-mini uses standard Chat Completions format with vision support
  const payload = {
    model: OPENAI_MODEL,
    messages: messages,
    max_completion_tokens: 4000,
    temperature: 0.7  // Add some personality while keeping responses focused
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


