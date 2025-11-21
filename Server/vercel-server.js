// Single entry point for all API routes on Vercel
module.exports = async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const path = url.pathname;

    // Set CORS headers for all requests
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-API-Key');
  
  if (req.method === 'OPTIONS') {
      return res.status(200).end();
    }

    // Health check endpoint
    if (path === '/api/healthz' || path === '/api/health') {
      return res.status(200).json({
      status: 'ok',
      timestamp: new Date().toISOString(),
        environment: 'Vercel',
        message: 'API health check successful',
        endpoints: [
          '/api/healthz',
          '/api/chat',
          '/api/analyze',
          '/api/embedding',
          '/api/memory',
          '/api/places',
          '/api/guide',
          '/api/streaming-chat',
          '/api/listen'
        ]
      });
    }

    // Debug/test endpoints removed for production

    // Route to appropriate handler with dynamic imports
    let handler;
    try {
      if (path === '/api/chat') {
        handler = require('./api/chat');
      } else if (path === '/api/analyze') {
        handler = require('./api/analyze');
      } else if (path === '/api/embedding') {
        handler = require('./api/embedding');
      } else if (path === '/api/memory' || path === '/api/memory/extract') {
        handler = require('./api/memory');
      } else if (path === '/api/memory/extract-transcript') {
        handler = require('./api/memory/extract-transcript');
      } else if (path.startsWith('/api/places')) {
        handler = require('./api/places');
      } else if (path === '/api/guide') {
        handler = require('./api/guide');
      } else if (path === '/api/streaming-chat') {
        handler = require('./api/streaming-chat');
      } else if (path.startsWith('/api/listen')) {
        handler = require('./api/listen');
      }

      if (handler) {
        return await handler(req, res);
      }
    } catch (importError) {
      console.error('Import error for path:', path, importError);
      return res.status(500).json({ 
        error: 'Handler Import Failed',
        path: path,
        message: importError.message
      });
    }

    // Default response for unknown routes
    return res.status(404).json({ 
      error: 'Not Found', 
      path: path,
      available: ['/api/healthz', '/api/chat', '/api/analyze', '/api/embedding', '/api/memory', '/api/places', '/api/guide', '/api/streaming-chat', '/api/listen']
    });

  } catch (error) {
    console.error('Vercel server error:', error);
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    return res.status(500).json({ 
      error: 'Internal Server Error',
      message: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
};