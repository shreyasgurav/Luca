// Sentry integration for production error tracking
const logger = require('./logger');

class SentryManager {
  constructor() {
    this.sentry = null;
    this.initialized = false;
    this.init();
  }

  init() {
    const sentryDsn = process.env.SENTRY_DSN;
    if (!sentryDsn || process.env.NODE_ENV !== 'production') {
      logger.info('Sentry not initialized - DSN missing or not in production');
      return;
    }

    try {
      // Only require Sentry if DSN is configured
      const Sentry = require('@sentry/node');
      
      Sentry.init({
        dsn: sentryDsn,
        environment: process.env.NODE_ENV || 'development',
        release: process.env.npm_package_version || '1.0.0',
        tracesSampleRate: 0.1, // 10% performance monitoring
        beforeSend: (event) => {
          // Sanitize sensitive data
          if (event.request) {
            delete event.request.headers?.authorization;
            delete event.request.headers?.['x-api-key'];
          }
          return event;
        }
      });

      this.sentry = Sentry;
      this.initialized = true;
      logger.info('Sentry initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize Sentry', { error: error.message });
    }
  }

  captureException(error, context = {}) {
    if (this.initialized && this.sentry) {
      this.sentry.captureException(error, {
        tags: {
          component: 'luca-server'
        },
        extra: context
      });
    }
    
    // Always log locally as well
    logger.error('Exception captured', { error: error.message, stack: error.stack, context });
  }

  captureMessage(message, level = 'info', context = {}) {
    if (this.initialized && this.sentry) {
      this.sentry.captureMessage(message, level, {
        tags: {
          component: 'luca-server'
        },
        extra: context
      });
    }
    
    logger[level](message, context);
  }

  addBreadcrumb(message, category = 'default', data = {}) {
    if (this.initialized && this.sentry) {
      this.sentry.addBreadcrumb({
        message,
        category,
        data,
        timestamp: Date.now() / 1000
      });
    }
  }

  // Express/HTTP middleware
  requestHandler() {
    if (this.initialized && this.sentry) {
      return this.sentry.Handlers.requestHandler();
    }
    return (req, res, next) => next();
  }

  errorHandler() {
    if (this.initialized && this.sentry) {
      return this.sentry.Handlers.errorHandler();
    }
    return (error, req, res, next) => {
      this.captureException(error, { url: req.url, method: req.method });
      next(error);
    };
  }

  setUser(userId, email = null, username = null) {
    if (this.initialized && this.sentry) {
      this.sentry.setUser({ id: userId, email, username });
    }
  }

  setTag(key, value) {
    if (this.initialized && this.sentry) {
      this.sentry.setTag(key, value);
    }
  }
}

module.exports = new SentryManager();
