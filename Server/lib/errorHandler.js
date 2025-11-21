// Production error handling utilities
class ErrorHandler {
  static createUserFriendlyError(error, context = {}) {
    // Map technical errors to user-friendly messages
    const errorMap = {
      'ENOTFOUND': 'Network connection error. Please check your internet connection.',
      'ECONNREFUSED': 'Service temporarily unavailable. Please try again later.',
      'ETIMEDOUT': 'Request timed out. Please try again.',
      'AbortError': 'Request was cancelled due to timeout.',
      'Invalid API key': 'Authentication failed. Please check your API key.',
      'Rate limit exceeded': 'Too many requests. Please wait a moment and try again.',
      'Token limit exceeded': 'Message too long. Please shorten your request.',
      'Model overloaded': 'AI service is busy. Please try again in a few moments.'
    };

    // Check for specific error patterns
    for (const [pattern, message] of Object.entries(errorMap)) {
      if (error.message?.includes(pattern) || error.code === pattern || error.name === pattern) {
        return {
          userMessage: message,
          technicalError: error.message,
          code: pattern,
          context
        };
      }
    }

    // OpenAI specific errors
    if (error.message?.includes('OpenAI error')) {
      const statusMatch = error.message.match(/OpenAI error (\d+):/);
      if (statusMatch) {
        const status = parseInt(statusMatch[1]);
        const statusMessages = {
          400: 'Invalid request. Please check your message and try again.',
          401: 'Authentication failed. Please check your API key.',
          403: 'Access denied. Your API key may not have the required permissions.',
          429: 'Rate limit exceeded. Please wait a moment and try again.',
          500: 'AI service error. Please try again later.',
          503: 'AI service temporarily unavailable. Please try again later.'
        };
        
        return {
          userMessage: statusMessages[status] || 'AI service error. Please try again later.',
          technicalError: error.message,
          code: `HTTP_${status}`,
          context
        };
      }
    }

    // Generic fallback
    return {
      userMessage: 'An unexpected error occurred. Please try again.',
      technicalError: error.message,
      code: 'UNKNOWN_ERROR',
      context
    };
  }

  static sendErrorResponse(res, error, statusCode = 500, context = {}) {
    const friendlyError = this.createUserFriendlyError(error, context);
    
    // Log technical details (but don't expose to user)
    console.error('API Error:', {
      ...friendlyError,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });

    // Send user-friendly response
    res.writeHead(statusCode, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      error: friendlyError.userMessage,
      code: friendlyError.code,
      ...(process.env.NODE_ENV === 'development' && { 
        technical: friendlyError.technicalError,
        stack: error.stack 
      })
    }));
  }

  static wrapAsyncHandler(handler) {
    return async (req, res) => {
      try {
        await handler(req, res);
      } catch (error) {
        this.sendErrorResponse(res, error, 500, { 
          endpoint: req.url, 
          method: req.method 
        });
      }
    };
  }

  static validateRequest(req, requiredFields = []) {
    const errors = [];
    
    // Check content type for POST requests
    if (req.method === 'POST' && !req.headers['content-type']?.includes('application/json') && !req.headers['content-type']?.includes('multipart/form-data')) {
      errors.push('Content-Type must be application/json or multipart/form-data');
    }

    // Validate required fields would go here after parsing body
    // This is a placeholder for request validation logic
    
    return errors;
  }
}

module.exports = ErrorHandler;
