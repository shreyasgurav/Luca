// Production monitoring and metrics
class MonitoringMiddleware {
  constructor() {
    this.metrics = {
      requests: { total: 0, success: 0, error: 0 },
      endpoints: {},
      errors: [],
      uptime: Date.now()
    };
    
    // Clean old errors every hour (disabled in tests to avoid open handles)
    if (process.env.NODE_ENV !== 'test') {
      this._cleanupTimer = setInterval(() => this.cleanOldErrors(), 60 * 60 * 1000);
    }
  }

  recordRequest(req, res, duration, error = null) {
    const endpoint = this.normalizeEndpoint(req.url);
    
    // Update global metrics
    this.metrics.requests.total++;
    if (error) {
      this.metrics.requests.error++;
      this.recordError(error, req);
    } else {
      this.metrics.requests.success++;
    }
    
    // Update endpoint metrics
    if (!this.metrics.endpoints[endpoint]) {
      this.metrics.endpoints[endpoint] = { count: 0, avgDuration: 0, errors: 0 };
    }
    
    const endpointMetrics = this.metrics.endpoints[endpoint];
    endpointMetrics.count++;
    endpointMetrics.avgDuration = (endpointMetrics.avgDuration * (endpointMetrics.count - 1) + duration) / endpointMetrics.count;
    
    if (error) {
      endpointMetrics.errors++;
    }
  }

  recordError(error, req) {
    const errorRecord = {
      timestamp: Date.now(),
      message: error.message,
      stack: error.stack,
      endpoint: req.url,
      method: req.method,
      userAgent: req.headers['user-agent'],
      ip: req.headers['x-forwarded-for'] || req.connection.remoteAddress
    };
    
    this.metrics.errors.push(errorRecord);
    
    // Log to console in development
    if (process.env.NODE_ENV === 'development') {
      console.error('API Error:', errorRecord);
    }
  }

  cleanOldErrors() {
    const oneHourAgo = Date.now() - (60 * 60 * 1000);
    this.metrics.errors = this.metrics.errors.filter(e => e.timestamp > oneHourAgo);
  }

  normalizeEndpoint(url) {
    // Normalize URLs for better grouping
    return url.replace(/\/[0-9a-f-]{36}/g, '/:id') // UUIDs
              .replace(/\/\d+/g, '/:id') // Numeric IDs
              .split('?')[0]; // Remove query params
  }

  getHealthStatus() {
    const now = Date.now();
    const uptimeSeconds = Math.floor((now - this.metrics.uptime) / 1000);
    const recentErrors = this.metrics.errors.filter(e => e.timestamp > now - 5 * 60 * 1000); // Last 5 minutes
    
    return {
      status: recentErrors.length > 10 ? 'degraded' : 'healthy',
      uptime: uptimeSeconds,
      requests: this.metrics.requests,
      recentErrors: recentErrors.length,
      endpoints: Object.keys(this.metrics.endpoints).length,
      memory: process.memoryUsage(),
      timestamp: now
    };
  }

  getMetrics() {
    return {
      ...this.metrics,
      health: this.getHealthStatus()
    };
  }

  middleware(req, res, next) {
    const startTime = Date.now();
    
    // Override res.end to capture response
    const originalEnd = res.end;
    res.end = (chunk, encoding) => {
      const duration = Date.now() - startTime;
      const error = res.statusCode >= 400 ? new Error(`HTTP ${res.statusCode}`) : null;
      this.recordRequest(req, res, duration, error);
      originalEnd.call(res, chunk, encoding);
    };
    
    next();
  }
}

module.exports = new MonitoringMiddleware();
