# Server Testing Guide

## 🚀 Quick Start Testing

### 1. **Prerequisites Check**
```bash
cd Server
node --version  # Should be >= 16.0.0
npm --version   # Should be >= 8.0.0
```

### 2. **Install Dependencies**
```bash
npm install
```

### 3. **Environment Setup**
Create a `.env` file in the Server directory:
```bash
# Required for OpenAI API
OPENAI_API_KEY=your_actual_openai_api_key_here

# Optional configurations
PORT=3000
CORS_ORIGIN=*
OPENAI_MODEL=gpt-4o-mini
```

## 🧪 Testing Methods

### **Method 1: Automated Tests (Recommended)**

#### Run All Tests
```bash
npm test
```

#### Run Specific Test Suites
```bash
# API endpoint tests
npm run test:integration

# Load testing
npm run test:load

# Watch mode for development
npm run test:watch
```

### **Method 2: Manual Server Testing**

#### Start the Server
```bash
# Development mode (with auto-restart)
npm run dev

# Production mode
npm start
```

#### Test Endpoints Manually
```bash
# Health check
curl http://localhost:3000/api/health

# Memory extraction (requires OpenAI API key)
curl -X POST http://localhost:3000/api/memory \
  -H "Content-Type: application/json" \
  -d '{"content": "My name is John and I love coffee", "userId": "test123"}'

# Chat endpoint
curl -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, how are you?", "userId": "test123"}'
```

### **Method 3: Health Check Only**
```bash
npm run health-check
```

## 🔧 Available Test Suites

### 1. **API Tests** (`api.test.js`)
- Tests all API endpoints
- Validates request/response formats
- Checks error handling
- Tests authentication middleware

### 2. **Integration Tests** (`integration.test.js`)
- End-to-end workflow testing
- Tests complete user journeys
- Validates data flow between components
- Tests with real API calls (requires OpenAI key)

### 3. **Load Tests** (`load.test.js`)
- Performance testing under load
- Tests concurrent requests
- Memory usage monitoring
- Response time validation

### 4. **Setup File** (`setup.js`)
- Test environment configuration
- Global test utilities
- Mock data setup
- Environment variables for testing

## 📊 Test Coverage

The server includes comprehensive testing for:

- ✅ **Health endpoints** - Basic server functionality
- ✅ **Memory extraction** - AI-powered memory processing
- ✅ **Chat API** - Conversational AI functionality
- ✅ **Authentication** - User session management
- ✅ **Error handling** - Graceful failure scenarios
- ✅ **CORS** - Cross-origin request handling
- ✅ **Rate limiting** - API abuse prevention
- ✅ **Load balancing** - Performance under stress

## 🚨 Troubleshooting

### Common Issues:

#### 1. **OpenAI API Key Missing**
```bash
Error: OpenAI API key not configured
```
**Solution**: Set `OPENAI_API_KEY` in your `.env` file

#### 2. **Port Already in Use**
```bash
Error: listen EADDRINUSE :::3000
```
**Solution**: 
```bash
# Kill process using port 3000
lsof -ti:3000 | xargs kill -9

# Or use a different port
PORT=3001 npm start
```

#### 3. **Dependencies Missing**
```bash
Error: Cannot find module
```
**Solution**:
```bash
rm -rf node_modules package-lock.json
npm install
```

#### 4. **Tests Failing**
```bash
# Check test setup
npm run test -- --verbose

# Run specific failing test
npm test -- --testNamePattern="specific test name"
```

## 🔍 Manual Testing Checklist

### Basic Functionality:
- [ ] Server starts without errors
- [ ] Health endpoint responds
- [ ] CORS headers are present
- [ ] Error handling works for invalid requests

### API Endpoints:
- [ ] `/api/health` - Returns 200 OK
- [ ] `/api/memory` - Processes content correctly
- [ ] `/api/chat` - Handles conversations
- [ ] `/api/embedding` - Generates embeddings
- [ ] `/api/listen` - WebSocket connection works

### Performance:
- [ ] Response times under 2 seconds
- [ ] Memory usage stable
- [ ] No memory leaks during load testing
- [ ] Concurrent request handling

## 🎯 Testing Results Interpretation

### ✅ **Success Indicators:**
- All tests pass (green checkmarks)
- Response times < 2 seconds
- Memory usage stable
- No error logs in console

### ⚠️ **Warning Signs:**
- Some tests failing
- Response times > 5 seconds
- Memory usage increasing over time
- Frequent error logs

### ❌ **Failure Indicators:**
- All tests failing
- Server crashes on startup
- API endpoints returning 500 errors
- Memory usage continuously increasing

## 🚀 Production Deployment Testing

### Pre-deployment Checklist:
```bash
# 1. Run full test suite
npm test

# 2. Security audit
npm run security

# 3. Lint check
npm run lint

# 4. Load test
npm run test:load

# 5. Health check
npm run health-check
```

### Docker Testing:
```bash
# Build Docker image
npm run docker:build

# Run in Docker
npm run docker:run

# Stop Docker
npm run docker:stop
```

## 📝 Next Steps After Testing

1. **If tests pass**: Server is ready for deployment
2. **If tests fail**: Fix issues before proceeding
3. **If performance is poor**: Optimize before production
4. **If security issues found**: Address vulnerabilities

Your server testing is now complete! 🎉
