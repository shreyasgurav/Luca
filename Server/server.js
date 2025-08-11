require('dotenv').config();
const http = require('http');
const analyze = require('./functions/analyze');
const chat = require('./functions/chat');
const memory = require('./functions/memory');
const embedding = require('./functions/embedding');

const server = http.createServer((req, res) => {
  if (req.url === '/api/analyze') return analyze(req, res);
  if (req.url === '/api/chat') return chat(req, res);
  if (req.url === '/api/memory/extract') return memory(req, res);
  if (req.url === '/api/embedding') return embedding(req, res);
  if (req.url === '/api/test') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ status: 'ok', model: process.env.OPENAI_MODEL || 'o3' }));
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

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server listening on http://localhost:${port}`));


