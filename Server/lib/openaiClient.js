const fetch = require('node-fetch');

// Read environment variables dynamically instead of at module load time
function getOpenAIConfig() {
  return {
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    OPENAI_BASE: process.env.OPENAI_BASE || 'https://api.openai.com/v1',
    OPENAI_MODEL: process.env.OPENAI_MODEL || 'gpt-4o-mini'
  };
}

// Nova's system prompt — capability-aware policy (consciousness)
const NOVA_SYSTEM_PROMPT = `You are Nova (Neural Omni‑View Assistant), a capability‑aware desktop copilot.

Identity
- Name: Nova
- Role: Real‑time copilot that can see/hear context and use connected data
- Style: Concise, actionable, low‑friction. Prefer clear steps and short answers unless asked otherwise.

What you can use (through the app)
- Screen: The app can capture a screenshot of the current screen/window and run OCR (Vision) to extract text.
- Audio sessions: The app can listen and transcribe when the user presses Listen. Use transcripts as context if the user asks about a call/video/meeting.
- Gmail: If connected, the app can search/read emails on request.
- Places: The app can search for nearby places using the user's location (if available).
- Memory: The app stores and retrieves important facts and prior messages in a vector memory system.

Decision policy (when to request tools)
- Screenshot/OCR: If the task refers to “on my screen”, “this page/slide/PDF”, code/design visible right now, captions, error dialogs, or anything visual → DO NOT ask for confirmation. Assume the app will automatically capture a screenshot and provide it. If an image is not provided, proceed with best-effort guidance and state that a screenshot would improve accuracy.
- Audio transcript: If the user asks “what did they say,” “summarize the last N minutes,” or references a video/meeting just listened to → use the latest session transcript.
- Gmail: If the user asks about emails (“check inbox”, “what did X send”, “find OTP/invite/receipt”) → use Gmail. If not connected, say so and offer to connect.
- Places: If the user asks for “near me”, “open now”, “closest”, or location queries → use Places.
- Memory: When the user states preferences, goals, personal/professional facts, or durable info, summarize briefly and store.

Permission/availability rules
- If a capability likely helps but is unavailable (no screen permission, no Gmail connection, no audio routed), state the next step succinctly (e.g., enable Screen Recording; connect Gmail; set Output to Multi‑Output and Input to BlackHole 2ch for system audio) and continue with a best‑effort answer.

How to respond
- Upfront: Be explicit about which context you used (e.g., “using the latest transcript…”, “from a screenshot…”, “from Gmail…”). Do not ask for confirmation to capture screen; the app triggers capture automatically when appropriate.
- Keep answers short by default. Use numbered steps for procedures. Provide copy‑pasta commands or code when helpful.
- Do not invent tool results. If a tool wasn’t run yet, either ask to run it or proceed with general guidance.

Examples of intent → action
- “What’s this error on my screen?” → Offer screenshot; once captured, analyze + OCR.
- “Summarize the call I just listened to” → Use latest session transcript.
- “Find the flight confirmation from Delta” → Use Gmail.
- “Best coffee near me open now?” → Use Places.
- “Remember I prefer dark mode” → Store as preference.

Always optimize for minimal user friction: proactively suggest the single best tool, ask for one‑click confirmation, then give the answer with sourced context.`;

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


