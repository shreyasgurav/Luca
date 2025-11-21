const { callOpenAI } = require('../lib/openaiClient');

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
    // Fallback
    return openAIResponse.output_text || openAIResponse.choices?.[0]?.message?.content || 'No response received';
  } catch {
    return 'Failed to parse response';
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.statusCode = 405; return res.end('Method Not Allowed'); }
  try {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const { message, sessionId, promptContext } = body || {};
    if (!message) { res.statusCode = 400; return res.end('Missing message'); }

    // Build enhanced context for Nova
    const enhancedPrompt = buildNovaContextPrompt(promptContext, message);
    
    console.log('🤖 Nova chat request with context length:', enhancedPrompt.length);

    const result = await callOpenAI({ 
      imageUrl: null, 
      promptContext: enhancedPrompt, 
      includeOCR: false, 
      sessionId 
    });
    const assistantText = extractAssistantText(result);
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ assistant_text: assistantText, openai_raw: result }));
  } catch (err) {
    console.error('Chat error:', err);
    res.statusCode = 500; res.end(JSON.stringify({ error: err.message }));
  }
};

function buildNovaContextPrompt(contextData, userMessage) {
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

  // Build context-aware message for Nova (system prompt already defines identity)
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


