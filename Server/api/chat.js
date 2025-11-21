const { callOpenAI } = require('./lib/openaiClient');
const { handleCorsAndAuth } = require('./lib/auth');

function extractAssistantText(openAIResponse) {
  try {
    // Extract from o3 Responses API format
    if (openAIResponse.output && Array.isArray(openAIResponse.output)) {
      const messageOutput = openAIResponse.output.find(item => item.type === 'message');
      if (messageOutput && messageOutput.content && Array.isArray(messageOutput.content)) {
        const textContent = messageOutput.content.find(item => item.type === 'output_text');
        if (textContent && textContent.text) {
          return textContent.text;
        }
      }
    }
    
    // Get the raw response text
    const rawText = openAIResponse.output_text || openAIResponse.choices?.[0]?.message?.content || 'No response received';
    
    // If it's JSON from the guided procedure system, extract the instruction
    try {
      const parsed = JSON.parse(rawText);
      if (parsed.next_step && parsed.next_step.instruction) {
        return parsed.next_step.instruction;
      }
      if (parsed.mode === 'plain_answer' && parsed.goal_summary) {
        return parsed.goal_summary;
      }
    } catch {
      // Not JSON, return as-is
    }
    
    return rawText;
  } catch {
    return 'Failed to parse response';
  }
}

module.exports = async function handler(req, res) {
  const ok = await handleCorsAndAuth(req, res);
  if (!ok) return;
  if (req.method !== 'POST') { res.statusCode = 405; return res.end('Method Not Allowed'); }
  try {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const { message, sessionId, promptContext } = body || {};
    if (!message) { res.statusCode = 400; return res.end('Missing message'); }

    // Build enhanced context for Luca
    const enhancedPrompt = truncate(buildLucaContextPrompt(promptContext, message), 6000);
    
    console.log('🤖 Luca chat request with context length:', enhancedPrompt.length);

    const result = await callOpenAI({ 
      imageUrl: null, 
      promptContext: enhancedPrompt, 
      includeOCR: false, 
      sessionId 
    });
    const assistantText = extractAssistantText(result);
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ assistant_text: assistantText }));
  } catch (err) {
    console.error('Chat error:', err);
    res.statusCode = 500; res.end(JSON.stringify({ error: err.message }));
  }
};

function buildLucaContextPrompt(contextData, userMessage) {
  if (!contextData || contextData.trim() === '') {
    return userMessage;
  }

  // Parse the context data to extract different sections
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
      case 'profile':
        userProfile += line + '\n';
        break;
      case 'relevant':
        relevantContext += line + '\n';
        break;
      case 'conversation':
        recentConversation += line + '\n';
        break;
    }
  }

  // Build context-aware message for Luca (system prompt already defines identity)
  let contextualMessage = '';
  
  if (userProfile.trim()) {
    contextualMessage += `[User Profile: ${userProfile.trim()}]\n\n`;
  }
  
  if (relevantContext.trim()) {
    contextualMessage += `[Relevant Context: ${relevantContext.trim()}]\n\n`;
  }
  
  if (recentConversation.trim()) {
    contextualMessage += `[Recent Conversation:\n${recentConversation.trim()}]\n\n`;
  }
  
  contextualMessage += userMessage;

  return contextualMessage;
}

function truncate(s = '', n = 6000) {
  if (!s) return '';
  return s.length <= n ? s : s.slice(0, n) + '\n...[truncated]';
}


