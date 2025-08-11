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

    const result = await callOpenAI({ imageUrl: null, promptContext: `${promptContext || ''}\nUser: ${message}`, includeOCR: false, sessionId });
    const assistantText = extractAssistantText(result);
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ assistant_text: assistantText, openai_raw: result }));
  } catch (err) {
    console.error(err);
    res.statusCode = 500; res.end(JSON.stringify({ error: err.message }));
  }
}


