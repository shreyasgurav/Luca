const { callOpenAI } = require('./lib/openaiClient');

// Streaming chat endpoint for better UX
module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { 
    res.statusCode = 405; 
    return res.end('Method Not Allowed'); 
  }

  try {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const { message, sessionId, promptContext } = body || {};
    
    if (!message) { 
      res.statusCode = 400; 
      return res.end('Missing message'); 
    }

    // Set up Server-Sent Events
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-API-Key'
    });

    // Send initial event
    res.write('data: {"type":"start","message":"Processing..."}\n\n');

    // Build enhanced context
    const enhancedPrompt = truncate(buildLucaContextPrompt(promptContext, message), 6000);
    
    console.log('🤖 Streaming chat request with context length:', enhancedPrompt.length);

    try {
      // Call OpenAI with streaming
      const result = await callOpenAIStreaming({ 
        promptContext: enhancedPrompt, 
        sessionId,
        onChunk: (chunk) => {
          // Stream each chunk to client
          res.write(`data: ${JSON.stringify({type: 'chunk', content: chunk})}\n\n`);
        }
      });

      // Send completion event
      res.write(`data: ${JSON.stringify({type: 'complete', fullResponse: result})}\n\n`);
      res.write('data: [DONE]\n\n');
      
    } catch (error) {
      console.error('Streaming chat error:', error);
      res.write(`data: ${JSON.stringify({type: 'error', message: error.message})}\n\n`);
    }
    
    res.end();
    
  } catch (err) {
    console.error('Streaming setup error:', err);
    res.statusCode = 500; 
    res.end(JSON.stringify({ error: err.message }));
  }
};

// Real OpenAI streaming implementation
async function callOpenAIStreaming({ promptContext, sessionId, onChunk }) {
  const streamingClient = require('../lib/streaming');
  
  return new Promise((resolve, reject) => {
    streamingClient.streamChat({
      promptContext,
      sessionId,
      onChunk: (chunk) => {
        onChunk(chunk);
      },
      onComplete: (fullResponse) => {
        resolve(fullResponse);
      },
      onError: (error) => {
        reject(error);
      }
    });
  });
}

function extractAssistantText(openAIResponse) {
  try {
    if (openAIResponse.choices && Array.isArray(openAIResponse.choices)) {
      const choice = openAIResponse.choices[0];
      if (choice && choice.message && choice.message.content) {
        return choice.message.content;
      }
    }
    return openAIResponse.output_text || openAIResponse.choices?.[0]?.message?.content || 'No response received';
  } catch {
    return 'Failed to parse response';
  }
}

function buildLucaContextPrompt(contextData, userMessage) {
  if (!contextData || contextData.trim() === '') {
    return userMessage;
  }

  const lines = contextData.split('\n');
  let userProfile = '';
  let relevantContext = '';
  let recentConversation = '';
  let currentSection = '';
  
  for (const line of lines) {
    if (line.startsWith('User Profile:')) {
      currentSection = 'profile';
      continue;
    } else if (line.startsWith('Relevant Context:')) {
      currentSection = 'relevant';
      continue;
    } else if (line.startsWith('Recent Conversation:')) {
      currentSection = 'conversation';
      continue;
    }
    
    if (line.trim() === '') continue;
    
    switch (currentSection) {
      case 'profile': userProfile += line + '\n'; break;
      case 'relevant': relevantContext += line + '\n'; break;
      case 'conversation': recentConversation += line + '\n'; break;
    }
  }

  let contextualMessage = '';
  if (userProfile.trim()) contextualMessage += `[User Profile: ${userProfile.trim()}]\n\n`;
  if (relevantContext.trim()) contextualMessage += `[Relevant Context: ${relevantContext.trim()}]\n\n`;
  if (recentConversation.trim()) contextualMessage += `[Recent Conversation:\n${recentConversation.trim()}]\n\n`;
  contextualMessage += userMessage;

  return contextualMessage;
}

function truncate(s = '', n = 6000) {
  if (!s) return '';
  return s.length <= n ? s : s.slice(0, n) + '\n...[truncated]';
}
