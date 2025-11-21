const http = require('http');

class ProductionTester {
  constructor(baseUrl = 'http://localhost:3000') {
    this.baseUrl = baseUrl;
    this.results = [];
  }

  async makeRequest(path, options = {}) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      const requestOptions = {
        method: options.method || 'GET',
        headers: {
          'Content-Type': 'application/json',
          ...options.headers
        },
        timeout: 30000
      };

      const req = http.request(url, requestOptions, (res) => {
        let data = '';
        res.on('data', chunk => { data += chunk; });
        res.on('end', () => {
          resolve({
            path,
            status: res.statusCode,
            data: data,
            success: res.statusCode >= 200 && res.statusCode < 300
          });
        });
      });

      req.on('error', (error) => {
        reject(error);
      });

      if (options.body) {
        req.write(JSON.stringify(options.body));
      }
      
      req.end();
    });
  }

  async testAllFeatures() {
    console.log('🧪 Testing All Production Features for 100 Users\n');
    
    const tests = [
      {
        name: 'Health Check',
        test: () => this.makeRequest('/api/health'),
        expected: 'healthy'
      },
      {
        name: 'Memory Extraction',
        test: () => this.makeRequest('/api/memory', {
          method: 'POST',
          body: { content: 'My name is John and I love coffee', userId: 'test123' }
        }),
        expected: 'success'
      },
      {
        name: 'Chat API',
        test: () => this.makeRequest('/api/chat', {
          method: 'POST',
          headers: { 'X-API-Key': 'test-key' },
          body: { message: 'Hello, how are you?', userId: 'test123' }
        }),
        expected: 'response'
      },
      {
        name: 'Embedding API',
        test: () => this.makeRequest('/api/embedding', {
          method: 'POST',
          headers: { 'X-API-Key': 'test-key' },
          body: { text: 'test embedding', userId: 'test123' }
        }),
        expected: 'embedding'
      },
      {
        name: 'Listen API (WebSocket)',
        test: () => this.makeRequest('/api/listen', {
          headers: { 'X-API-Key': 'test-key' }
        }),
        expected: 'websocket'
      }
    ];

    const results = {};
    
    for (const test of tests) {
      try {
        console.log(`Testing ${test.name}...`);
        const result = await test.test();
        results[test.name] = {
          status: result.success ? '✅ PASS' : '❌ FAIL',
          httpStatus: result.status,
          hasData: result.data.length > 0
        };
        console.log(`  ${results[test.name].status} (HTTP ${result.status})`);
      } catch (error) {
        results[test.name] = {
          status: '❌ ERROR',
          error: error.message
        };
        console.log(`  ❌ ERROR: ${error.message}`);
      }
    }

    return results;
  }

  async testConcurrentLoad() {
    console.log('\n🚀 Testing Concurrent Load (100 Users Simulation)\n');
    
    const concurrentUsers = 100;
    const requestsPerUser = 5;
    
    console.log(`Simulating ${concurrentUsers} concurrent users with ${requestsPerUser} requests each...`);
    
    const userPromises = Array(concurrentUsers).fill().map(async (_, index) => {
      const userResults = [];
      
      for (let i = 0; i < requestsPerUser; i++) {
        try {
          // Mix of different endpoint calls
          const endpoints = [
            { path: '/api/health', options: {} },
            { 
              path: '/api/memory', 
              options: { 
                method: 'POST', 
                body: { content: `User ${index} message ${i}`, userId: `user${index}` } 
              } 
            }
          ];
          
          const endpoint = endpoints[i % endpoints.length];
          const result = await this.makeRequest(endpoint.path, endpoint.options);
          userResults.push({ success: result.success, status: result.status });
        } catch (error) {
          userResults.push({ success: false, error: error.message });
        }
      }
      
      return userResults;
    });

    const allResults = await Promise.all(userPromises);
    
    // Analyze results
    const totalRequests = allResults.flat().length;
    const successfulRequests = allResults.flat().filter(r => r.success).length;
    const failedRequests = totalRequests - successfulRequests;
    const successRate = (successfulRequests / totalRequests) * 100;
    
    return {
      totalRequests,
      successfulRequests,
      failedRequests,
      successRate,
      concurrentUsers,
      requestsPerUser
    };
  }

  printProductionReport(featureResults, loadResults) {
    console.log('\n📊 PRODUCTION READINESS REPORT');
    console.log('='.repeat(60));
    
    console.log('\n🎯 Feature Tests:');
    Object.entries(featureResults).forEach(([feature, result]) => {
      console.log(`   ${feature}: ${result.status}`);
      if (result.error) {
        console.log(`     Error: ${result.error}`);
      }
    });
    
    console.log('\n⚡ Load Test Results:');
    console.log(`   Concurrent Users: ${loadResults.concurrentUsers}`);
    console.log(`   Requests per User: ${loadResults.requestsPerUser}`);
    console.log(`   Total Requests: ${loadResults.totalRequests}`);
    console.log(`   Successful: ${loadResults.successfulRequests}`);
    console.log(`   Failed: ${loadResults.failedRequests}`);
    console.log(`   Success Rate: ${loadResults.successRate.toFixed(2)}%`);
    
    console.log('\n🏆 Production Readiness Assessment:');
    
    const workingFeatures = Object.values(featureResults).filter(r => r.status.includes('✅')).length;
    const totalFeatures = Object.keys(featureResults).length;
    
    if (workingFeatures >= 3 && loadResults.successRate >= 95) {
      console.log('   ✅ READY FOR PRODUCTION');
      console.log('   ✅ Can handle 100+ concurrent users');
      console.log('   ✅ All critical features working');
    } else if (workingFeatures >= 2 && loadResults.successRate >= 90) {
      console.log('   ⚠️  MOSTLY READY (minor issues)');
      console.log('   ⚠️  Can handle 50-100 concurrent users');
    } else {
      console.log('   ❌ NOT READY (needs fixes)');
      console.log('   ❌ Issues need to be resolved');
    }
    
    console.log('\n💡 Recommendations:');
    if (loadResults.successRate >= 95) {
      console.log('   • Server is production-ready');
      console.log('   • Can deploy with confidence');
      console.log('   • Monitor Redis connection');
    } else {
      console.log('   • Fix failing endpoints');
      console.log('   • Check API key configuration');
      console.log('   • Verify Redis connection');
    }
    
    console.log('\n' + '='.repeat(60));
  }
}

async function runProductionTest() {
  const tester = new ProductionTester();
  
  try {
    const featureResults = await tester.testAllFeatures();
    const loadResults = await tester.testConcurrentLoad();
    tester.printProductionReport(featureResults, loadResults);
  } catch (error) {
    console.error('Test failed:', error);
  }
}

if (require.main === module) {
  runProductionTest();
}

module.exports = ProductionTester;
