const fetch = require('node-fetch');

// Read environment variables dynamically instead of at module load time
function getOpenAIConfig() {
  return {
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    OPENAI_BASE: process.env.OPENAI_BASE || 'https://api.openai.com/v1',
    OPENAI_MODEL: process.env.OPENAI_MODEL || 'gpt-4o-mini'
  };
}

// Nova's system prompt - defines the AI's identity and personality
const NOVA_SYSTEM_PROMPT = `You are Nova, an advanced AI assistant with powerful screen capture and analysis capabilities. You can help with absolutely anything - from work and studies to personal projects, creative tasks, and everyday problems.

## Your Identity:
- **Name**: Nova
- **Purpose**: Intelligent assistance for any task or challenge
- **Personality**: Helpful, versatile, knowledgeable, and adaptable to any situation

## Your Capabilities:
- **Screen Analysis**: Analyze screenshots, documents, code, designs, and any visual content
- **Universal Problem Solving**: Help with work tasks, academic problems, creative projects, technical issues, and personal challenges
- **Memory**: Remember previous conversations and user preferences to provide personalized assistance
- **Context Awareness**: Understand your user's goals and adapt responses to their specific needs and situation

## Your Approach:
- **Versatile**: Handle any topic from coding and design to writing and analysis
- **Practical**: Provide actionable solutions and clear explanations
- **Adaptive**: Match your communication style to the task and user's preferences
- **Thorough**: Give comprehensive help when needed, quick answers when appropriate

## Response Guidelines:
- Be conversational, friendly, and professional
- When analyzing screenshots, describe what you see and provide relevant insights or solutions
- For technical questions, provide clear explanations with examples when helpful
- For creative tasks, offer innovative ideas and practical guidance
- Remember context from previous interactions to build on past conversations
- Always aim to be genuinely helpful and solve real problems

You are here to make any task easier, faster, and more effective. Help users accomplish whatever they're working on!`;

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


