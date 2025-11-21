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
    const { image_base64, promptContext, includeOCR, sessionId } = body || {};
    
    if (!image_base64) { 
      res.statusCode = 400; 
      return res.end('Missing image_base64'); 
    }

    // Convert base64 to data URL
    const imageUrl = `data:image/png;base64,${image_base64}`;
    
    console.log(`📸 Analyzing screenshot: ${image_base64.length} bytes, OCR: ${includeOCR || false}`);
    
    // Call OpenAI with image analysis
    const openAIResponse = await callOpenAI({
      imageUrl: imageUrl,
      promptContext: promptContext || 'Please analyze this screenshot and help me understand what I\'m looking at.',
      includeOCR: includeOCR || false,
      sessionId: sessionId || null
    });
    
    const assistantText = extractAssistantText(openAIResponse);
    
    console.log(`✅ Analysis complete: ${assistantText.length} chars`);
    
    // Return the response in the expected format
    res.statusCode = 200;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({
      success: true,
      assistant_text: assistantText,
      sessionId: sessionId || null,
      timestamp: new Date().toISOString()
    }));
    
  } catch (error) {
    console.error('❌ Analyze API error:', error);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({
      success: false,
      error: error.message || 'Analysis failed',
      timestamp: new Date().toISOString()
    }));
  }
};
