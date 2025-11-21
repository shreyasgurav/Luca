// Redis client for production persistence
const redis = require('redis');

class RedisManager {
  constructor() {
    this.client = null;
    this.connected = false;
  }

  async connect() {
    if (this.connected) return;

    try {
      const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
      this.client = redis.createClient({
        url: redisUrl,
        retry_strategy: (times) => {
          const delay = Math.min(times * 50, 2000);
          return delay;
        }
      });

      this.client.on('error', (err) => {
        console.error('Redis Client Error:', err);
        this.connected = false;
      });

      this.client.on('connect', () => {
        console.log('✅ Connected to Redis');
        this.connected = true;
      });

      await this.client.connect();
    } catch (error) {
      console.error('❌ Redis connection failed:', error);
      // Graceful degradation - continue without Redis
      this.connected = false;
    }
  }

  async get(key) {
    if (!this.connected) return null;
    try {
      return await this.client.get(key);
    } catch (error) {
      console.error('Redis GET error:', error);
      return null;
    }
  }

  async set(key, value, expirySeconds = 3600) {
    if (!this.connected) return false;
    try {
      await this.client.setEx(key, expirySeconds, value);
      return true;
    } catch (error) {
      console.error('Redis SET error:', error);
      return false;
    }
  }

  async increment(key, expirySeconds = 3600) {
    if (!this.connected) return 1;
    try {
      const result = await this.client.incr(key);
      if (result === 1) {
        // Set expiry on first increment
        await this.client.expire(key, expirySeconds);
      }
      return result;
    } catch (error) {
      console.error('Redis INCR error:', error);
      return 1; // Fallback to allow request
    }
  }

  async delete(key) {
    if (!this.connected) return false;
    try {
      await this.client.del(key);
      return true;
    } catch (error) {
      console.error('Redis DEL error:', error);
      return false;
    }
  }

  isConnected() {
    return this.connected;
  }

  async disconnect() {
    if (this.client && this.connected) {
      await this.client.disconnect();
      this.connected = false;
    }
  }
}

// Enhanced auth with Redis persistence
class PersistentAuthMiddleware {
  constructor() {
    this.redis = new RedisManager();
    this.validApiKeys = new Set((process.env.LUCA_API_KEYS || '').split(',').filter(k => k.length > 0));
    this.requestsPerMinute = parseInt(process.env.RATE_LIMIT_RPM || '60');
    this.requestsPerHour = parseInt(process.env.RATE_LIMIT_RPH || '1000');
    
    // Initialize Redis connection
    this.redis.connect().catch(console.error);
  }

  async checkRateLimit(identifier) {
    const now = Date.now();
    const minuteKey = `rate:${identifier}:${Math.floor(now / (60 * 1000))}`;
    const hourKey = `rate:${identifier}:${Math.floor(now / (60 * 60 * 1000))}`;

    try {
      // Use Redis for distributed rate limiting
      const [minuteCount, hourCount] = await Promise.all([
        this.redis.increment(minuteKey, 60),
        this.redis.increment(hourKey, 3600)
      ]);

      if (minuteCount > this.requestsPerMinute) {
        return { allowed: false, reason: 'Rate limit exceeded (per minute)' };
      }
      if (hourCount > this.requestsPerHour) {
        return { allowed: false, reason: 'Rate limit exceeded (per hour)' };
      }

      return { allowed: true };
    } catch (error) {
      console.error('Rate limit check failed:', error);
      // Graceful degradation - allow request if Redis fails
      return { allowed: true };
    }
  }

  isValidApiKey(apiKey) {
    if (!apiKey) return false;
    return this.validApiKeys.has(apiKey) || apiKey === process.env.LUCA_MASTER_KEY;
  }

  async authenticate(req, res, next) {
    try {
      // Skip auth for health check
      if (req.url === '/api/health' || req.url === '/api/healthz') {
        return next();
      }

      const apiKey = req.headers['x-api-key'] || req.headers['authorization']?.replace('Bearer ', '');
      const clientIp = req.headers['x-forwarded-for'] || req.connection.remoteAddress || 'unknown';
      
      // Check API key
      if (!this.isValidApiKey(apiKey)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Invalid or missing API key' }));
      }

      // Rate limiting with Redis
      const identifier = apiKey || clientIp;
      const rateCheck = await this.checkRateLimit(identifier);
      
      if (!rateCheck.allowed) {
        res.writeHead(429, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: rateCheck.reason }));
      }

      req.auth = { apiKey, clientIp, identifier };
      next();
    } catch (error) {
      console.error('Auth middleware error:', error);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Authentication service error' }));
    }
  }
}

module.exports = { RedisManager, PersistentAuthMiddleware };
