// Minimal Express-style serverless handler (works on Vercel/Netlify adapters or Node Express)
const Busboy = require('busboy');
const { callOpenAI } = require('../lib/openaiClient');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.statusCode = 405; res.end('Method Not Allowed'); return;
  }

  try {
    console.log('📸 Starting screenshot analysis...');
    const { fields, file } = await parseMultipart(req);
    if (!file || !file.buffer) { res.statusCode = 400; res.end('Missing image'); return; }
    if (file.buffer.length > 10 * 1024 * 1024) { res.statusCode = 413; res.end('File too large'); return; }
    
    console.log(`📷 Image received: ${file.buffer.length} bytes, type: ${file.mimetype}`);

    // If S3/R2 env not provided, fall back to data URL (no external storage required)
    let imageUrl;
    if (process.env.S3_BUCKET) {
      const { uploadBufferAndGetURL } = require('../lib/storage');
      imageUrl = await uploadBufferAndGetURL(file.buffer, file.filename, file.mimetype);
    } else {
      const base64 = file.buffer.toString('base64');
      const contentType = file.mimetype || 'image/jpeg';
      imageUrl = `data:${contentType};base64,${base64}`;
    }

    const promptContext = fields.promptContext || `Analyze this screenshot and help the user. If this contains:
- Multiple choice questions (MCQs): Solve them step by step and provide the correct answer with explanation
- Math problems: Show step-by-step solution and final answer
- Code: Explain what it does, find bugs, or suggest improvements
- Text/Documents: Summarize key points or answer questions about the content
- UI/Interface: Describe functionality and help with navigation
- Diagrams/Charts: Explain the data and insights
- General images: Describe what you see and provide relevant analysis

Be helpful, accurate, and provide actionable information. Focus on solving problems rather than just describing what you see.`;
    const includeOCR = fields.includeOCR === 'true';
    const sessionId = fields.sessionId || null;

    console.log('🤖 Calling OpenAI for image analysis...');
    const startTime = Date.now();
    const openAIResponse = await callOpenAI({ imageUrl, promptContext, includeOCR, sessionId });
    const duration = Date.now() - startTime;
    console.log(`✅ OpenAI analysis completed in ${duration}ms`);
    
    const assistantText = extractAssistantText(openAIResponse);

    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ assistant_text: assistantText, structured: null, openai_raw: openAIResponse }));
  } catch (err) {
    console.error(err);
    res.statusCode = 500;
    res.end(JSON.stringify({ error: err.message }));
  }
}

function parseMultipart(req) {
  return new Promise((resolve, reject) => {
    const busboy = Busboy({ headers: req.headers });
    const fields = {};
    let fileData = null;

    busboy.on('field', (name, val) => { fields[name] = val; });
    busboy.on('file', (name, file, info) => {
      const chunks = [];
      file.on('data', (d) => chunks.push(d));
      file.on('end', () => {
        fileData = { buffer: Buffer.concat(chunks), filename: info.filename, mimetype: info.mimeType };
      });
    });
    busboy.on('finish', () => resolve({ fields, file: fileData }));
    busboy.on('error', reject);
    req.pipe(busboy);
  });
}

function extractAssistantText(openAIResponse) {
  try {
    // Extract from GPT-4V Chat Completions format
    if (openAIResponse.choices && Array.isArray(openAIResponse.choices)) {
      const choice = openAIResponse.choices[0];
      if (choice && choice.message && choice.message.content) {
        return choice.message.content;
      }
    }
    
    // Extract from O3 Responses API format
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


