const config = require('./config');
const http = require('http');
const analyze = require('./functions/analyze');
const chat = require('./functions/chat');
const memory = require('./functions/memory');
const embedding = require('./functions/embedding');
const gmail = require('./functions/gmail');
const places = require('./functions/places');
const listen = require('./functions/listen');

// Set environment variables from config for compatibility
process.env.OPENAI_API_KEY = config.OPENAI_API_KEY;
process.env.OPENAI_BASE = config.OPENAI_BASE;
process.env.OPENAI_MODEL = config.OPENAI_MODEL;
process.env.PORT = config.PORT;
process.env.S3_BUCKET = config.S3_BUCKET;
process.env.S3_REGION = config.S3_REGION;
process.env.S3_ACCESS_KEY = config.S3_ACCESS_KEY;
process.env.S3_SECRET_KEY = config.S3_SECRET_KEY;

const server = http.createServer((req, res) => {
  // Add CORS headers
  res.setHeader('Access-Control-Allow-Origin', config.CORS_ORIGIN);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    res.end();
    return;
  }
  
  if (req.url === '/api/analyze') return analyze(req, res);
  if (req.url === '/api/chat') return chat(req, res);
  if (req.url === '/api/memory/extract') return memory(req, res);
  if (req.url === '/api/embedding') return embedding(req, res);
  if (req.url.startsWith('/api/gmail')) return gmail(req, res);
  if (req.url.startsWith('/api/places')) return places(req, res);
  if (req.url.startsWith('/api/listen')) return listen(req, res);
  if (req.url === '/api/test') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ 
      status: 'ok', 
      model: config.OPENAI_MODEL,
      api_configured: !!config.OPENAI_API_KEY && config.OPENAI_API_KEY !== 'your-openai-api-key-here'
    }));
  }
  if (req.url.startsWith('/debug/listMemories')) {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ 
      message: 'Debug endpoint - would list memories from Firestore',
      note: 'Implement with Firebase Admin SDK if needed'
    }));
  }
  res.statusCode = 404; res.end('Not found');
});

const port = config.PORT;
server.listen(port, () => {
  console.log(`🚀 CheatingAI Server running on http://localhost:${port}`);
  console.log(`🔑 OpenAI API: ${config.OPENAI_API_KEY ? 'Configured' : 'NOT CONFIGURED'}`);
  console.log(`🤖 Model: ${config.OPENAI_MODEL}`);
  if (!config.OPENAI_API_KEY || config.OPENAI_API_KEY === 'your-openai-api-key-here') {
    console.log('⚠️  WARNING: Please configure your OpenAI API key in config.js');
  }
});


