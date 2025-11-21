const http = require('http');
const { performance } = require('perf_hooks');

class StressTester {
  constructor(baseUrl = 'http://localhost:3000') {
    this.baseUrl = baseUrl;
    this.results = [];
    this.serverStats = {
      startTime: null,
      endTime: null,
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      avgResponseTime: 0,
      maxResponseTime: 0,
      minResponseTime: Infinity,
      requestsPerSecond: 0,
      memoryUsage: [],
      cpuUsage: []
    };
  }

  async makeRequest(path, options = {}) {
    const start = performance.now();
    
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);
      const requestOptions = {
        method: options.method || 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': 'test-api-key',
          ...options.headers
        },
        timeout: 30000 // 30 second timeout
      };

      const req = http.request(url, requestOptions, (res) => {
        let data = '';
        res.on('data', chunk => { data += chunk; });
        res.on('end', () => {
          const end = performance.now();
          const duration = end - start;
          
          const result = {
            path,
            status: res.statusCode,
            duration,
            size: data.length,
            success: res.statusCode >= 200 && res.statusCode < 300,
            timestamp: start
          };
          
          this.results.push(result);
          this.updateStats(result);
          resolve(result);
        });
      });

      req.on('error', (error) => {
        const end = performance.now();
        const result = {
          path,
          status: 0,
          duration: end - start,
          size: 0,
          success: false,
          error: error.message,
          timestamp: start
        };
        
        this.results.push(result);
        this.updateStats(result);
        reject(error);
      });

      req.on('timeout', () => {
        req.destroy();
        const end = performance.now();
        const result = {
          path,
          status: 0,
          duration: end - start,
          size: 0,
          success: false,
          error: 'Request timeout',
          timestamp: start
        };
        
        this.results.push(result);
        this.updateStats(result);
        reject(new Error('Request timeout'));
      });

      if (options.body) {
        req.write(JSON.stringify(options.body));
      }
      
      req.end();
    });
  }

  updateStats(result) {
    this.serverStats.totalRequests++;
    
    if (result.success) {
      this.serverStats.successfulRequests++;
    } else {
      this.serverStats.failedRequests++;
    }

    // Update response time stats
    this.serverStats.avgResponseTime = 
      (this.serverStats.avgResponseTime * (this.serverStats.totalRequests - 1) + result.duration) / this.serverStats.totalRequests;
    
    this.serverStats.maxResponseTime = Math.max(this.serverStats.maxResponseTime, result.duration);
    this.serverStats.minResponseTime = Math.min(this.serverStats.minResponseTime, result.duration);
  }

  async runStressTest(testConfig) {
    const { 
      endpoint, 
      options = {}, 
      concurrentUsers = 10, 
      requestsPerUser = 100, 
      rampUpTime = 1000,
      testDuration = 60000 
    } = testConfig;

    console.log(`🚀 Starting stress test:`);
    console.log(`   Endpoint: ${endpoint}`);
    console.log(`   Concurrent Users: ${concurrentUsers}`);
    console.log(`   Requests per User: ${requestsPerUser}`);
    console.log(`   Total Requests: ${concurrentUsers * requestsPerUser}`);
    console.log(`   Test Duration: ${testDuration}ms`);
    console.log(`   Ramp-up Time: ${rampUpTime}ms`);
    console.log('');

    this.serverStats.startTime = performance.now();
    
    // Create user simulation
    const users = Array(concurrentUsers).fill().map((_, index) => ({
      id: index + 1,
      requests: requestsPerUser,
      completed: 0
    }));

    // Start all users with ramp-up
    const userPromises = users.map(async (user, index) => {
      // Stagger user start times
      await new Promise(resolve => setTimeout(resolve, (index * rampUpTime) / concurrentUsers));
      
      const userResults = [];
      
      for (let i = 0; i < user.requests; i++) {
        try {
          const result = await this.makeRequest(endpoint, options);
          userResults.push(result);
          user.completed++;
          
          // Small delay between requests from same user
          await new Promise(resolve => setTimeout(resolve, 100));
        } catch (error) {
          userResults.push({
            path: endpoint,
            success: false,
            error: error.message,
            duration: 0,
            timestamp: performance.now()
          });
          user.completed++;
        }
      }
      
      return userResults;
    });

    // Wait for test completion or timeout
    const timeoutPromise = new Promise((resolve) => {
      setTimeout(() => {
        console.log('⏰ Test timeout reached');
        resolve([]);
      }, testDuration);
    });

    const results = await Promise.race([
      Promise.all(userPromises),
      timeoutPromise
    ]);

    this.serverStats.endTime = performance.now();
    this.calculateFinalStats();
    
    return this.generateReport();
  }

  calculateFinalStats() {
    const totalDuration = this.serverStats.endTime - this.serverStats.startTime;
    this.serverStats.requestsPerSecond = this.serverStats.totalRequests / (totalDuration / 1000);
    
    // Calculate percentiles
    const durations = this.results
      .filter(r => r.success)
      .map(r => r.duration)
      .sort((a, b) => a - b);
    
    if (durations.length > 0) {
      this.serverStats.p50ResponseTime = durations[Math.floor(durations.length * 0.5)];
      this.serverStats.p90ResponseTime = durations[Math.floor(durations.length * 0.9)];
      this.serverStats.p95ResponseTime = durations[Math.floor(durations.length * 0.95)];
      this.serverStats.p99ResponseTime = durations[Math.floor(durations.length * 0.99)];
    }
  }

  generateReport() {
    const report = {
      testSummary: {
        totalRequests: this.serverStats.totalRequests,
        successfulRequests: this.serverStats.successfulRequests,
        failedRequests: this.serverStats.failedRequests,
        successRate: (this.serverStats.successfulRequests / this.serverStats.totalRequests) * 100,
        testDuration: this.serverStats.endTime - this.serverStats.startTime
      },
      performance: {
        requestsPerSecond: this.serverStats.requestsPerSecond,
        avgResponseTime: this.serverStats.avgResponseTime,
        minResponseTime: this.serverStats.minResponseTime === Infinity ? 0 : this.serverStats.minResponseTime,
        maxResponseTime: this.serverStats.maxResponseTime,
        p50ResponseTime: this.serverStats.p50ResponseTime || 0,
        p90ResponseTime: this.serverStats.p90ResponseTime || 0,
        p95ResponseTime: this.serverStats.p95ResponseTime || 0,
        p99ResponseTime: this.serverStats.p99ResponseTime || 0
      },
      capacity: this.assessCapacity()
    };

    return report;
  }

  assessCapacity() {
    const successRate = (this.serverStats.successfulRequests / this.serverStats.totalRequests) * 100;
    const avgResponseTime = this.serverStats.avgResponseTime;
    const rps = this.serverStats.requestsPerSecond;

    let capacityRating = 'UNKNOWN';
    let maxConcurrentUsers = 'UNKNOWN';
    let recommendations = [];

    if (successRate >= 99 && avgResponseTime < 1000) {
      capacityRating = 'EXCELLENT';
      maxConcurrentUsers = '500+ users';
      recommendations.push('Server can handle high load');
      recommendations.push('Consider load balancing for scale');
    } else if (successRate >= 95 && avgResponseTime < 2000) {
      capacityRating = 'GOOD';
      maxConcurrentUsers = '100-500 users';
      recommendations.push('Server handles moderate load well');
      recommendations.push('Monitor under peak usage');
    } else if (successRate >= 90 && avgResponseTime < 5000) {
      capacityRating = 'FAIR';
      maxConcurrentUsers = '50-100 users';
      recommendations.push('Server handles light load');
      recommendations.push('Consider optimization');
    } else {
      capacityRating = 'POOR';
      maxConcurrentUsers = '< 50 users';
      recommendations.push('Server needs optimization');
      recommendations.push('Check for bottlenecks');
    }

    return {
      rating: capacityRating,
      estimatedMaxConcurrentUsers: maxConcurrentUsers,
      currentRPS: Math.round(rps),
      recommendations
    };
  }

  printReport(report) {
    console.log('\n📊 STRESS TEST REPORT');
    console.log('='.repeat(50));
    
    console.log('\n🎯 Test Summary:');
    console.log(`   Total Requests: ${report.testSummary.totalRequests}`);
    console.log(`   Successful: ${report.testSummary.successfulRequests}`);
    console.log(`   Failed: ${report.testSummary.failedRequests}`);
    console.log(`   Success Rate: ${report.testSummary.successRate.toFixed(2)}%`);
    console.log(`   Test Duration: ${(report.testSummary.testDuration / 1000).toFixed(2)}s`);
    
    console.log('\n⚡ Performance Metrics:');
    console.log(`   Requests/Second: ${report.performance.requestsPerSecond.toFixed(2)}`);
    console.log(`   Avg Response Time: ${report.performance.avgResponseTime.toFixed(2)}ms`);
    console.log(`   Min Response Time: ${report.performance.minResponseTime.toFixed(2)}ms`);
    console.log(`   Max Response Time: ${report.performance.maxResponseTime.toFixed(2)}ms`);
    console.log(`   P50 Response Time: ${report.performance.p50ResponseTime?.toFixed(2) || 'N/A'}ms`);
    console.log(`   P90 Response Time: ${report.performance.p90ResponseTime?.toFixed(2) || 'N/A'}ms`);
    console.log(`   P95 Response Time: ${report.performance.p95ResponseTime?.toFixed(2) || 'N/A'}ms`);
    console.log(`   P99 Response Time: ${report.performance.p99ResponseTime?.toFixed(2) || 'N/A'}ms`);
    
    console.log('\n🏆 Server Capacity Assessment:');
    console.log(`   Rating: ${report.capacity.rating}`);
    console.log(`   Max Concurrent Users: ${report.capacity.estimatedMaxConcurrentUsers}`);
    console.log(`   Current RPS: ${report.capacity.currentRPS}`);
    
    if (report.capacity.recommendations.length > 0) {
      console.log('\n💡 Recommendations:');
      report.capacity.recommendations.forEach(rec => {
        console.log(`   • ${rec}`);
      });
    }
    
    console.log('\n' + '='.repeat(50));
  }
}

// Test configurations
const testConfigs = [
  {
    name: 'Light Load Test',
    config: {
      endpoint: '/api/health',
      options: {},
      concurrentUsers: 10,
      requestsPerUser: 20,
      rampUpTime: 1000,
      testDuration: 30000
    }
  },
  {
    name: 'Moderate Load Test',
    config: {
      endpoint: '/api/health',
      options: {},
      concurrentUsers: 50,
      requestsPerUser: 40,
      rampUpTime: 2000,
      testDuration: 60000
    }
  },
  {
    name: 'Heavy Load Test',
    config: {
      endpoint: '/api/health',
      options: {},
      concurrentUsers: 100,
      requestsPerUser: 50,
      rampUpTime: 5000,
      testDuration: 120000
    }
  },
  {
    name: 'Chat API Load Test',
    config: {
      endpoint: '/api/chat',
      options: {
        method: 'POST',
        body: { message: 'Load test message', userId: 'test-user' }
      },
      concurrentUsers: 25,
      requestsPerUser: 20,
      rampUpTime: 2000,
      testDuration: 60000
    }
  }
];

async function runAllStressTests() {
  console.log('🚀 Starting Comprehensive Server Stress Tests\n');
  
  for (const test of testConfigs) {
    console.log(`\n🧪 Running: ${test.name}`);
    console.log('-'.repeat(40));
    
    const tester = new StressTester();
    const report = await tester.runStressTest(test.config);
    tester.printReport(report);
    
    // Wait between tests
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
}

// Run tests if called directly
if (require.main === module) {
  runAllStressTests().catch(console.error);
}

module.exports = { StressTester, runAllStressTests };
