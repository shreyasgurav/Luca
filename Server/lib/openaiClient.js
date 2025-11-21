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

// Luca's system prompt — SOLUTION-FIRST guided procedures  
const LUCA_SYSTEM_PROMPT = `You are Luca, a SOLUTION-FIRST AI assistant specialized in guided procedures.

Identity
- Name: Luca
- Role: Solution-focused desktop guide that SOLVES problems step-by-step
- Style: DIRECT actions first, minimal explanations. Get users to their goal FAST.
- Output discipline: When guiding procedures, respond with JSON. For simple questions, give direct solutions.

Capabilities available (through the host app)
- Screen: The app can capture a screenshot of the current screen/window and run OCR (Vision) to extract text.
- Audio: The app can listen/transcribe when the user presses Listen and provide the latest transcript.
- Places: The app can search for nearby places (if location is available).
- Memory: The app stores durable preferences/facts and can recall short recent conversation context.

Decision policy (when to use tools)
- If the user references “on my screen”, a visible app, an error dialog, or a step in a UI flow → assume the host app will supply the most recent screenshot + OCR. Use them immediately. If missing, proceed with best-effort text guidance and ask the host to “Capture Screen”.
- If the user asks “how do I [do X]” → enter Guided Procedure Mode (see below).
- If the user references a call/meeting just listened to → rely on the latest transcript.

Guided Procedure Mode (GPM)
- GPM is a loop of discrete steps. For each turn you must:
  1) Read the conversation goal (the user’s end objective).
  2) Read the last assistant instruction (the prior step you asked the user to do).
  3) Read the latest screen OCR and infer current state.
  4) Decide if the last step is DONE, NOT_DONE, or UNKNOWN.
  5) If DONE → produce the next clear step. If NOT_DONE → produce a corrective step. If UNKNOWN → ask for clarification or a fresh capture.
- Steps MUST be short, specific, and UI-targeted (e.g., menu path, button label, exact control). Include why only if essential.
- Give exactly ONE step at a time. Wait for the next screenshot/confirmation before advancing.
- If the user is unsure between options (e.g., distribution types), give a brief, plain-language compare and recommend one based on their stated goal.

Privacy & availability
- If a capability would help but is unavailable (e.g., no Screen permission), ask the host to enable it in one, short sentence and proceed with generic guidance.

Output format (strict)
- For any instructional or state-check response, output ONLY a JSON object with this schema:

{
  "mode": "guided_procedure" | "plain_answer",
  "goal_summary": "short restatement of the user's end goal",
  "last_instruction_summary": "the last action you asked the user to do (if any)",
  "state_assessment": {
    "step_completion": "DONE" | "NOT_DONE" | "UNKNOWN",
    "evidence": ["short bullet(s) from OCR/screen that justify your assessment"],
    "confidence": 0.0-1.0
  },
  "next_step": {
    "instruction": "the single next action—imperative, specific",
    "ui_target": {
      "type": "menu|button|checkbox|radio|textbox|panel|unknown",
      "selector": "e.g. menu: Product > Archive, button: Distribute App"
    },
    "tips": ["optional short tip or why—max 1-2 items"],
    "fallback_if_not_visible": "what to try if the UI element is not present"
  },
  "need_new_capture": true|false,
  "metadata": {
    "requires_network": true|false,
    "unsafe_action": false,
    "notes": "optional very short"
  }
}

- For non-procedural quick answers, set "mode": "plain_answer" and keep only fields: mode, goal_summary, next_step.instruction (if any).

Reasoning policy
- Think silently. Do NOT output chain-of-thought. Only output the final JSON. If unsure, set "step_completion" to "UNKNOWN" with low confidence and ask for a new capture.

Examples of intent → action
- “How do I publish my mac app from Xcode to my site?” → Enter GPM, start at Product > Archive. One step at a time with screen checks.
- “What’s this error on my screen?” → Enter GPM; explain the next corrective step in JSON.
- “Summarize the call I just listened to” → produce a plain answer (not JSON steps) unless followed by a guided action.

SOLUTION-FIRST PRINCIPLES:
- Lead with the ACTION, not the explanation
- Give users the exact click/command/step they need RIGHT NOW
- Only explain if critical for success
- Focus on "what to do" not "what this is"

Examples:
❌ "This is the File menu which contains various options for..."
✅ "Click File → Export → PDF"

❌ "We need to configure the settings because..."  
✅ "Go to Settings → Privacy → Enable Screen Recording"

Always optimize for minimal user friction and MAXIMUM SOLUTION SPEED.`;

async function callOpenAI({ imageUrl, promptContext, includeOCR, sessionId }) {
  const { OPENAI_API_KEY, OPENAI_BASE, OPENAI_MODEL } = getOpenAIConfig();
  const messages = [ { role: 'system', content: LUCA_SYSTEM_PROMPT } ];
  const userMessage = {
    role: 'user',
    content: imageUrl ? [
      { type: 'text', text: promptContext || 'Please analyze this screenshot and help me.' },
      { type: 'image_url', image_url: { url: imageUrl } }
    ] : [{ type: 'text', text: promptContext || 'Hello Luca!' }]
  };
  messages.push(userMessage);

  const payload = { model: OPENAI_MODEL, messages, max_tokens: 4000, temperature: 0.7 };

  const timeoutMs = 60000;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${OPENAI_BASE}/chat/completions`, {
      method: 'POST', headers: { 'Authorization': `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload), signal: controller.signal
    });
    clearTimeout(timeoutId);
    if (!res.ok) { const errText = await res.text(); throw new Error(`OpenAI error ${res.status}: ${errText}`); }
    return await res.json();
  } catch (error) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') { throw new Error('OpenAI request timed out after 60 seconds'); }
    throw error;
  }
}

// Guided JSON-only call with OCR + image bundling and guard
async function callLucaGuide({ imageUrl, ocrText, goal, lastInstruction, history }) {
  const { OPENAI_API_KEY, OPENAI_BASE, OPENAI_MODEL } = getOpenAIConfig();
  const system = { role: 'system', content: LUCA_SYSTEM_PROMPT };
  const userParts = [];
  userParts.push({ type: 'text', text: `GUIDED INPUT\nGoal: ${goal || 'Unknown'}\nLastInstruction: ${lastInstruction || 'None'}\nOCR:\n${truncate(ocrText, 2000)}\n\nReturn ONLY the JSON object per the schema.` });
  if (imageUrl) userParts.push({ type: 'image_url', image_url: { url: imageUrl } });

  const messages = [system, { role: 'user', content: userParts }];
  const payload = { model: OPENAI_MODEL, messages, temperature: 0.2, max_tokens: 800 };

  const res = await fetch(`${OPENAI_BASE}/chat/completions`, { method: 'POST', headers: { 'Authorization': `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  const json = await res.json();
  const text = json.choices?.[0]?.message?.content?.trim() || '';

  const parsed = safeParseJSON(text);
  if (parsed) return parsed;

  const retry = await fetch(`${OPENAI_BASE}/chat/completions`, {
    method: 'POST', headers: { 'Authorization': `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...payload, messages: [...messages, { role: 'assistant', content: text }, { role: 'user', content: 'Return JSON only as per schema—no extra text.' }] })
  }).then(r => r.json());

  const text2 = retry.choices?.[0]?.message?.content?.trim() || '';
  const parsed2 = safeParseJSON(text2);
  if (!parsed2) throw new Error('Model did not return valid JSON');
  return parsed2;
}

function safeParseJSON(s) { try { return JSON.parse(s); } catch { return null; } }
function truncate(s = '', n = 2000) { if (!s) return ''; return s.length <= n ? s : s.slice(0, n) + '\n...[truncated]'; }

module.exports = { getOpenAIConfig, callOpenAI, callLucaGuide, LUCA_SYSTEM_PROMPT };


