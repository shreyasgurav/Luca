const request = require('supertest');
const http = require('http');

// Mock the OpenAI client
jest.mock('../lib/openaiClient', () => ({
  getOpenAIConfig: () => ({
    OPENAI_API_KEY: 'test-key',
    OPENAI_BASE: 'https://api.openai.com/v1',
    OPENAI_MODEL: 'gpt-4o-mini'
  }),
  callOpenAI: jest.fn().mockResolvedValue({
    choices: [{ message: { content: 'Test response' } }]
  })
}));

// Create test server
const corsMiddleware = require('../middleware/cors');
const monitoringMiddleware = require('../middleware/monitoring');
const authMiddleware = require('../middleware/auth');

const testServer = http.createServer((req, res) => {
  corsMiddleware.middleware(req, res, () => {
    monitoringMiddleware.middleware(req, res, () => {
      // Skip auth for tests
      if (req.url === '/api/health') {
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({ status: 'healthy' }));
      }
      
      if (req.url === '/api/test') {
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({ status: 'ok' }));
      }
      
      res.writeHead(404);
      res.end('Not Found');
    });
  });
});

describe('API Endpoints', () => {
  describe('Health Check', () => {
    test('GET /api/health returns healthy status', async () => {
      const response = await request(testServer)
        .get('/api/health')
        .expect(200);
      
      expect(response.body).toHaveProperty('status');
    });
  });

  describe('CORS', () => {
    test('Sets proper CORS headers', async () => {
      const response = await request(testServer)
        .options('/api/test')
        .set('Origin', 'http://localhost:3000');
      
      expect(response.headers['access-control-allow-origin']).toBeDefined();
      expect(response.headers['access-control-allow-methods']).toBeDefined();
    });

    test('Blocks unauthorized origins in production', async () => {
      process.env.NODE_ENV = 'production';
      
      const response = await request(testServer)
        .get('/api/test')
        .set('Origin', 'http://malicious-site.com');
      
      // Should either block or not set CORS headers for unauthorized origin
      expect(response.status).toBe(403);
      
      process.env.NODE_ENV = 'test';
    });
  });

  describe('Monitoring', () => {
    test('Records request metrics', async () => {
      await request(testServer).get('/api/health');
      
      // Monitoring should have recorded the request
      const metrics = monitoringMiddleware.getMetrics();
      expect(metrics.requests.total).toBeGreaterThan(0);
    });
  });

  describe('Error Handling', () => {
    test('Returns 404 for unknown endpoints', async () => {
      const response = await request(testServer)
        .get('/api/nonexistent')
        .expect(404);
      
      expect(response.text).toBe('Not Found');
    });
  });
});

describe('Security', () => {
  describe('Rate Limiting', () => {
    test('Auth middleware has rate limiting functionality', () => {
      const authInstance = require('../middleware/auth');
      expect(authInstance.checkRateLimit).toBeDefined();
      
      // Test rate limiting logic
      const result1 = authInstance.checkRateLimit('test-user');
      expect(result1.allowed).toBe(true);
    });
  });

  describe('Input Validation', () => {
    test('Validates content types', () => {
      const ErrorHandler = require('../lib/errorHandler');
      const mockReq = { method: 'POST', headers: {} };
      
      const errors = ErrorHandler.validateRequest(mockReq);
      expect(errors.length).toBeGreaterThan(0);
    });
  });
});
