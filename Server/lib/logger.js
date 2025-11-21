// Production logging with privacy controls
class Logger {
  constructor() {
    this.logLevel = process.env.LOG_LEVEL || 'info';
    this.levels = { error: 0, warn: 1, info: 2, debug: 3 };
    this.isProduction = process.env.NODE_ENV === 'production';
  }

  shouldLog(level) {
    return this.levels[level] <= this.levels[this.logLevel];
  }

  sanitizeData(data) {
    if (!data || typeof data !== 'object') return data;
    
    // Remove sensitive fields
    const sensitiveKeys = ['password', 'token', 'key', 'secret', 'auth', 'apikey'];
    const sanitized = { ...data };
    
    for (const key of Object.keys(sanitized)) {
      if (sensitiveKeys.some(sensitive => key.toLowerCase().includes(sensitive))) {
        sanitized[key] = '[REDACTED]';
      }
      
      // Truncate long strings in production
      if (this.isProduction && typeof sanitized[key] === 'string' && sanitized[key].length > 200) {
        sanitized[key] = sanitized[key].substring(0, 200) + '...[truncated]';
      }
    }
    
    return sanitized;
  }

  formatMessage(level, message, meta = {}) {
    const timestamp = new Date().toISOString();
    const sanitizedMeta = this.sanitizeData(meta);
    
    return JSON.stringify({
      timestamp,
      level: level.toUpperCase(),
      message,
      meta: sanitizedMeta,
      service: 'luca-server',
      version: process.env.npm_package_version || '1.0.0'
    });
  }

  error(message, meta = {}) {
    if (this.shouldLog('error')) {
      console.error(this.formatMessage('error', message, meta));
    }
  }

  warn(message, meta = {}) {
    if (this.shouldLog('warn')) {
      console.warn(this.formatMessage('warn', message, meta));
    }
  }

  info(message, meta = {}) {
    if (this.shouldLog('info')) {
      console.log(this.formatMessage('info', message, meta));
    }
  }

  debug(message, meta = {}) {
    if (this.shouldLog('debug')) {
      console.log(this.formatMessage('debug', message, meta));
    }
  }

  // Request logging helper
  logRequest(req, res, duration, error = null) {
    const logData = {
      method: req.method,
      url: req.url,
      userAgent: req.headers['user-agent'],
      ip: req.headers['x-forwarded-for'] || req.connection.remoteAddress,
      duration: `${duration}ms`,
      status: res.statusCode
    };

    if (error) {
      this.error('Request failed', { ...logData, error: error.message });
    } else {
      this.info('Request completed', logData);
    }
  }

  // API call logging
  logApiCall(endpoint, duration, success, error = null) {
    const logData = {
      endpoint,
      duration: `${duration}ms`,
      success
    };

    if (error) {
      this.error('API call failed', { ...logData, error: error.message });
    } else {
      this.info('API call completed', logData);
    }
  }
}

module.exports = new Logger();
