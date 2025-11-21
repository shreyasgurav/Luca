// Production-ready CORS middleware
class CORSMiddleware {
  constructor() {
    // Parse allowed origins from environment
    const originsEnv = process.env.ALLOWED_ORIGINS || 'http://localhost:3000,http://127.0.0.1:3000';
    this.allowedOrigins = new Set(originsEnv.split(',').map(o => o.trim()).filter(o => o.length > 0));
    
    // Development mode allows localhost variants
    if (process.env.NODE_ENV === 'development') {
      this.allowedOrigins.add('http://localhost:3000');
      this.allowedOrigins.add('http://127.0.0.1:3000');
      this.allowedOrigins.add('http://localhost:8080');
    }
  }

  isOriginAllowed(origin) {
    if (!origin) return true; // Allow same-origin requests
    return this.allowedOrigins.has(origin);
  }

  setCORSHeaders(req, res) {
    const origin = req.headers.origin;
    
    if (this.isOriginAllowed(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin || '*');
    }
    
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key');
    res.setHeader('Access-Control-Max-Age', '86400'); // 24 hours
    
    // Security headers
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');
  }

  middleware(req, res, next) {
    this.setCORSHeaders(req, res);
    
    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }
    
    // Block requests from unauthorized origins
    const origin = req.headers.origin;
    if (origin && !this.isOriginAllowed(origin)) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Origin not allowed' }));
      return;
    }
    
    next();
  }
}

module.exports = new CORSMiddleware();
