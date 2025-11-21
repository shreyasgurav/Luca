const http = require('http');
const https = require('https');
const { performance } = require('perf_hooks');

class CapacityTester {
  constructor(baseUrl = 'https://lucaserver1.vercel.app') {
    this.baseUrl = baseUrl;
    this.results = [];
  }

  async makeRequest(path, options = {}) {
    const start = performance.now();
    const url = new URL(path, this.baseUrl);
    
    return new Promise((resolve, reject) => {
      const requestOptions = {
        method: options.method || 'GET',
        headers: {
          'Content-Type': 'application/json',
          ...options.headers
        }
      };

      const client = url.protocol === 'https:' ? https : http;
      
      const req = client.request(url, requestOptions, (res) => {
        let data = '';
        res.on('data', chunk => { data += chunk; });
        res.on('end', () => {
          const end = performance.now();
          const result = {
            path,
            status: res.statusCode,
            duration: end - start,
            size: data.length,
            success: res.statusCode >= 200 && res.statusCode < 300
          };
          this.results.push(result);
          resolve(result);
        });
      });

      req.on('error', (error) => {
        const end = performance.now();
        this.results.push({
          path,
          status: 0,
          duration: end - start,
          size: 0,
          success: false,
          error: error.message
        });
        reject(error);
      });

      if (options.body) {
        req.write(JSON.stringify(options.body));
      }
      
      req.end();
    });
  }

  async runConcurrentTest(path, options, concurrency = 10, totalRequests = 100) {
    console.log(`🧪 Testing ${path} - ${totalRequests} requests, ${concurrency} concurrent`);
    
    const batches = Math.ceil(totalRequests / concurrency);
    const startTime = performance.now();

    for (let batch = 0; batch < batches; batch++) {
      const batchSize = Math.min(concurrency, totalRequests - (batch * concurrency));
      const promises = Array(batchSize).fill().map(() => 
        this.makeRequest(path, options).catch(() => {}) // Continue on error
      );
      
      await Promise.allSettled(promises);
      
      // Small delay between batches
      if (batch < batches - 1) {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }

    const endTime = performance.now();
    return this.analyzeResults(endTime - startTime);
  }

  analyzeResults(totalDuration) {
    const successful = this.results.filter(r => r.success);
    const failed = this.results.filter(r => !r.success);
    
    if (successful.length === 0) {
      return {
        success: false,
        error: 'All requests failed'
      };
    }

    const durations = successful.map(r => r.duration);
    const avgDuration = durations.reduce((a, b) => a + b, 0) / durations.length;
    const sortedDurations = durations.sort((a, b) => a - b);
    const p95Duration = sortedDurations[Math.floor(sortedDurations.length * 0.95)];
    const p99Duration = sortedDurations[Math.floor(sortedDurations.length * 0.99)];

    return {
      success: true,
      totalRequests: this.results.length,
      successfulRequests: successful.length,
      failedRequests: failed.length,
      successRate: (successful.length / this.results.length) * 100,
      avgResponseTime: Math.round(avgDuration * 100) / 100,
      p95ResponseTime: Math.round(p95Duration * 100) / 100,
      p99ResponseTime: Math.round(p99Duration * 100) / 100,
      requestsPerSecond: Math.round((this.results.length / (totalDuration / 1000)) * 100) / 100,
      totalDuration: Math.round(totalDuration)
    };
  }

  reset() {
    this.results = [];
  }
}

async function runCapacityTests() {
  console.log('🚀 Starting Server Capacity Analysis for Luca...\n');
  
  const tester = new CapacityTester('https://lucaserver1.vercel.app');
  
  // Test 1: Health endpoint (no auth, lightest load)
  console.log('📊 Testing Health Endpoint (Lightest Load)...');
  const healthResults = await tester.runConcurrentTest('/api/healthz', {}, 20, 200);
  console.log('✅ Health Results:', JSON.stringify(healthResults, null, 2));
  tester.reset();
  
  // Test 2: Embedding endpoint (no auth, medium load)
  console.log('\n📊 Testing Embedding Endpoint (Medium Load)...');
  const embeddingResults = await tester.runConcurrentTest('/api/embedding', {
    method: 'POST',
    body: { text: 'test message for capacity analysis', userId: 'capacity-test-user' }
  }, 10, 50);
  console.log('✅ Embedding Results:', JSON.stringify(embeddingResults, null, 2));
  tester.reset();
  
  // Test 3: Analyze endpoint (with auth, heavy load)
  console.log('\n📊 Testing Analyze Endpoint (Heavy Load)...');
  const analyzeResults = await tester.runConcurrentTest('/api/analyze', {
    method: 'POST',
    headers: { 'X-API-Key': '7c8e3f59-2e2b-4d1c-9f01-5a2a9f8d7c31' },
    body: { 
      image_base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAI9jU77zgAAAABJRU5ErkJggg==' 
    }
  }, 5, 20);
  console.log('✅ Analyze Results:', JSON.stringify(analyzeResults, null, 2));
  tester.reset();
  
  // Test 4: Chat endpoint (with auth, very heavy load)
  console.log('\n📊 Testing Chat Endpoint (Very Heavy Load)...');
  const chatResults = await tester.runConcurrentTest('/api/chat', {
    method: 'POST',
    headers: { 'X-API-Key': '7c8e3f59-2e2b-4d1c-9f01-5a2a9f8d7c31' },
    body: { 
      message: 'Hello, this is a capacity test message',
      sessionId: 'capacity-test-session'
    }
  }, 3, 15);
  console.log('✅ Chat Results:', JSON.stringify(chatResults, null, 2));
  tester.reset();
  
  console.log('\n🎯 Capacity Analysis Summary:');
  console.log('================================');
  console.log('📈 Health Endpoint:', healthResults.successRate + '% success, ' + healthResults.requestsPerSecond + ' RPS');
  console.log('📈 Embedding Endpoint:', embeddingResults.successRate + '% success, ' + embeddingResults.requestsPerSecond + ' RPS');
  console.log('📈 Analyze Endpoint:', analyzeResults.successRate + '% success, ' + analyzeResults.requestsPerSecond + ' RPS');
  console.log('📈 Chat Endpoint:', chatResults.successRate + '% success, ' + chatResults.requestsPerSecond + ' RPS');
  
  console.log('\n✅ Capacity tests completed!');
}

runCapacityTests().catch(console.error);
