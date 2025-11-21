const fetch = require('node-fetch');
const { getOpenAIConfig } = require('./openaiClient');

class StreamingClient {
  constructor() {
    this.LUCA_SYSTEM_PROMPT = `You are Luca, a SOLUTION-FIRST AI assistant. Your primary goal is to SOLVE problems, not just explain them.

CORE PRINCIPLES:
1. SOLUTION FIRST: Always lead with the fix/action/answer
2. Brief explanation ONLY if needed for context
3. Be direct, actionable, and practical
4. No unnecessary explanations unless specifically asked

RESPONSE FORMAT:
✅ SOLUTION: [Direct fix/action]
💡 Why: [Brief 1-line explanation only if helpful]

Be the assistant that gets things done, not the one that talks about doing things.`;
  }

  async streamChat({ promptContext, sessionId, onChunk, onComplete, onError }) {
    const { OPENAI_API_KEY, OPENAI_BASE, OPENAI_MODEL } = getOpenAIConfig();
    
    const messages = [
      { role: 'system', content: this.LUCA_SYSTEM_PROMPT },
      { role: 'user', content: promptContext || 'Hello Luca!' }
    ];

    const payload = {
      model: OPENAI_MODEL,
      messages: messages,
      max_tokens: 4000,
      temperature: 0.7,
      stream: true
    };

    try {
      const response = await fetch(`${OPENAI_BASE}/chat/completions`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`OpenAI API error: ${response.status} ${errorText}`);
      }

      let fullResponse = '';
      const reader = response.body;
      
      reader.on('data', (chunk) => {
        const lines = chunk.toString().split('\n');
        
        for (const line of lines) {
          const trimmedLine = line.trim();
          if (!trimmedLine || !trimmedLine.startsWith('data: ')) continue;
          
          const data = trimmedLine.slice(6);
          if (data === '[DONE]') {
            onComplete(fullResponse);
            return;
          }
          
          try {
            const parsed = JSON.parse(data);
            const content = parsed.choices?.[0]?.delta?.content;
            
            if (content) {
              fullResponse += content;
              onChunk(content);
            }
          } catch (e) {
            // Skip malformed JSON chunks
            console.warn('Skipping malformed SSE chunk:', data);
          }
        }
      });

      reader.on('error', (error) => {
        onError(error);
      });

      reader.on('end', () => {
        onComplete(fullResponse);
      });

    } catch (error) {
      onError(error);
    }
  }

  async streamAnalyze({ imageUrl, promptContext, includeOCR, sessionId, onChunk, onComplete, onError }) {
    const { OPENAI_API_KEY, OPENAI_BASE, OPENAI_MODEL } = getOpenAIConfig();
    
    const messages = [
      { role: 'system', content: this.LUCA_SYSTEM_PROMPT },
      {
        role: 'user',
        content: [
          { type: 'text', text: promptContext || 'Please analyze this screenshot and help me.' },
          { type: 'image_url', image_url: { url: imageUrl } }
        ]
      }
    ];

    const payload = {
      model: OPENAI_MODEL,
      messages: messages,
      max_tokens: 4000,
      temperature: 0.7,
      stream: true
    };

    try {
      const response = await fetch(`${OPENAI_BASE}/chat/completions`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`OpenAI API error: ${response.status} ${errorText}`);
      }

      let fullResponse = '';
      const reader = response.body;
      
      reader.on('data', (chunk) => {
        const lines = chunk.toString().split('\n');
        
        for (const line of lines) {
          const trimmedLine = line.trim();
          if (!trimmedLine || !trimmedLine.startsWith('data: ')) continue;
          
          const data = trimmedLine.slice(6);
          if (data === '[DONE]') {
            onComplete(fullResponse);
            return;
          }
          
          try {
            const parsed = JSON.parse(data);
            const content = parsed.choices?.[0]?.delta?.content;
            
            if (content) {
              fullResponse += content;
              onChunk(content);
            }
          } catch (e) {
            console.warn('Skipping malformed SSE chunk:', data);
          }
        }
      });

      reader.on('error', onError);
      reader.on('end', () => onComplete(fullResponse));

    } catch (error) {
      onError(error);
    }
  }
}

module.exports = new StreamingClient();
