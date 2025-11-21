const http = require('http');
const { getOpenAIConfig } = require('./lib/openaiClient');
const { PersistentAuthMiddleware } = require('./lib/redis');
const corsMiddleware = require('./middleware/cors');
const monitoringMiddleware = require('./middleware/monitoring');
const logger = require('./lib/logger');
const { initializeWebSocket } = require('./api/listen');

const { OPENAI_API_KEY, OPENAI_MODEL } = getOpenAIConfig();

// Initialize persistent auth
const authMiddleware = new PersistentAuthMiddleware();

const server = http.createServer((req, res) => {
  // Apply middleware in order
  corsMiddleware.middleware(req, res, () => {
    monitoringMiddleware.middleware(req, res, () => {
      authMiddleware.authenticate(req, res, () => {
        handleRoutes(req, res);
      });
    });
  });
});

// Initialize WebSocket server
initializeWebSocket(server);

function handleRoutes(req, res) {

  // Health check endpoint (no auth required)
  if (req.url === '/api/health') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify(monitoringMiddleware.getHealthStatus()));
  }

  // Test endpoint
  if (req.url === '/api/test') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ 
      status: 'ok', 
      model: OPENAI_MODEL,
      api_configured: !!OPENAI_API_KEY && OPENAI_API_KEY !== 'your-openai-api-key-here',
      environment: process.env.VERCEL ? 'Vercel' : 'Local'
    }));
  }

  // Metrics endpoint (for monitoring)
  if (req.url === '/api/metrics') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify(monitoringMiddleware.getMetrics()));
  }

  // Route to appropriate handler
  if (req.url === '/api/analyze') {
    require('./api/analyze')(req, res);
  } else if (req.url === '/api/chat') {
    require('./api/chat')(req, res);
  } else if (req.url === '/api/chat/stream') {
    require('./api/streaming-chat')(req, res);
  } else if (req.url === '/api/embedding') {
    require('./api/embedding')(req, res);
  } else if (req.url === '/api/places/search') {
    require('./api/places')(req, res);
  } else if (req.url === '/api/memory' || req.url === '/api/memory/extract') {
    // Unified memory endpoint
    require('./api/memory')(req, res);
  } else if (req.url === '/api/memory/extract-transcript') {
    require('./api/memory/extract-transcript')(req, res);
  } else {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Endpoint not found' }));
  }
}

// Graceful shutdown handling
process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

async function gracefulShutdown(signal) {
  logger.info(`Received ${signal}, starting graceful shutdown...`);
  
  server.close(() => {
    logger.info('HTTP server closed');
    
    // Close Redis connection
    if (authMiddleware.redis) {
      authMiddleware.redis.disconnect().then(() => {
        logger.info('Redis connection closed');
        process.exit(0);
      }).catch((err) => {
        logger.error('Error closing Redis connection', { error: err.message });
        process.exit(1);
      });
    } else {
      process.exit(0);
    }
  });

  // Force exit after 30 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
}

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  logger.info(`Luca Server started`, {
    port: PORT,
    environment: process.env.NODE_ENV || 'development',
    model: OPENAI_MODEL,
    apiConfigured: !!(OPENAI_API_KEY && OPENAI_API_KEY !== 'your-openai-api-key-here')
  });
  
  if (!OPENAI_API_KEY || OPENAI_API_KEY === 'your-openai-api-key-here') {
    logger.warn('OpenAI API key not configured');
  }
});


