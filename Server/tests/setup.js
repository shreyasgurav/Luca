// Jest setup for production-ready testing
const logger = require('../lib/logger');

// Mock console methods to prevent test noise
global.console = {
  ...console,
  log: jest.fn(),
  warn: jest.fn(),
  error: jest.fn()
};

// Set test environment variables
process.env.NODE_ENV = 'test';
process.env.OPENAI_API_KEY = 'test-key-12345';
process.env.LUCA_API_KEYS = 'test-api-key,test-key-2';
process.env.LUCA_MASTER_KEY = 'test-master-key';
process.env.RATE_LIMIT_RPM = '100';
process.env.RATE_LIMIT_RPH = '1000';
process.env.LOG_LEVEL = 'error'; // Reduce noise in tests

// Global test timeout
jest.setTimeout(30000);

// Clean up after tests
afterAll(async () => {
  // Close any open connections
  await new Promise(resolve => setTimeout(resolve, 1000));
});

// Global error handler for unhandled promises
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit in tests
});

// Mock Redis for tests that don't need real Redis
jest.mock('../lib/redis', () => {
  const mockRedis = {
    connect: jest.fn().mockResolvedValue(true),
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(true),
    increment: jest.fn().mockResolvedValue(1),
    delete: jest.fn().mockResolvedValue(true),
    isConnected: jest.fn().mockReturnValue(false),
    disconnect: jest.fn().mockResolvedValue(true)
  };

  const mockAuth = {
    redis: mockRedis,
    checkRateLimit: jest.fn().mockResolvedValue({ allowed: true }),
    isValidApiKey: jest.fn().mockReturnValue(true),
    authenticate: jest.fn().mockImplementation((req, res, next) => {
      req.auth = { apiKey: 'test-key', clientIp: '127.0.0.1' };
      next();
    })
  };

  return {
    RedisManager: jest.fn().mockImplementation(() => mockRedis),
    PersistentAuthMiddleware: jest.fn().mockImplementation(() => mockAuth)
  };
});
