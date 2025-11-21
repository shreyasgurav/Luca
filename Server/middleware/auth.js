const crypto = require('crypto');

// Simple API key authentication and rate limiting
class AuthMiddleware {
  constructor() {
    this.validApiKeys = new Set((process.env.LUCA_API_KEYS || '').split(',').filter(k => k.length > 0));
    this.rateLimitMap = new Map(); // ip -> { count, resetTime }
    this.requestsPerMinute = parseInt(process.env.RATE_LIMIT_RPM || '60');
    this.requestsPerHour = parseInt(process.env.RATE_LIMIT_RPH || '1000');
  }

  // Extract API key from request
  extractApiKey(req) {
    return req.headers['x-api-key'] || req.headers['authorization']?.replace('Bearer ', '');
  }

  // Check if API key is valid
  isValidApiKey(apiKey) {
    if (!apiKey) return false;
    return this.validApiKeys.has(apiKey) || apiKey === process.env.LUCA_MASTER_KEY;
  }

  // Rate limiting check
  checkRateLimit(identifier) {
    const now = Date.now();
    const minuteWindow = 60 * 1000;
    const hourWindow = 60 * 60 * 1000;
    
    if (!this.rateLimitMap.has(identifier)) {
      this.rateLimitMap.set(identifier, {
        minuteCount: 0,
        hourCount: 0,
        minuteReset: now + minuteWindow,
        hourReset: now + hourWindow
      });
    }

    const limits = this.rateLimitMap.get(identifier);
    
    // Reset counters if windows expired
    if (now > limits.minuteReset) {
      limits.minuteCount = 0;
      limits.minuteReset = now + minuteWindow;
    }
    if (now > limits.hourReset) {
      limits.hourCount = 0;
      limits.hourReset = now + hourWindow;
    }

    // Check limits
    if (limits.minuteCount >= this.requestsPerMinute) {
      return { allowed: false, reason: 'Rate limit exceeded (per minute)' };
    }
    if (limits.hourCount >= this.requestsPerHour) {
      return { allowed: false, reason: 'Rate limit exceeded (per hour)' };
    }

    // Increment counters
    limits.minuteCount++;
    limits.hourCount++;
    
    return { allowed: true };
  }

  // Main middleware function
  authenticate(req, res, next) {
    try {
      // Skip auth for health check
      if (req.url === '/api/health') {
        return next();
      }

      const apiKey = this.extractApiKey(req);
      const clientIp = req.headers['x-forwarded-for'] || req.connection.remoteAddress || 'unknown';
      
      // Check API key
      if (!this.isValidApiKey(apiKey)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Invalid or missing API key' }));
      }

      // Rate limiting (use API key as identifier, fallback to IP)
      const identifier = apiKey || clientIp;
      const rateCheck = this.checkRateLimit(identifier);
      
      if (!rateCheck.allowed) {
        res.writeHead(429, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: rateCheck.reason }));
      }

      // Add request metadata
      req.auth = { apiKey, clientIp, identifier };
      next();
    } catch (error) {
      console.error('Auth middleware error:', error);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Authentication service error' }));
    }
  }
}

module.exports = new AuthMiddleware();
