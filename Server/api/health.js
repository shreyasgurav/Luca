// Simple health check endpoint for Vercel
module.exports = async (req, res) => {
  // Add CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  res.status(200).json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: process.env.VERCEL ? 'Vercel' : 'Local',
    message: 'API health check successful',
    endpoints: [
      '/api/health',
      '/api/analyze',
      '/api/chat',
      '/api/embedding',
      '/api/memory',
      '/api/places'
    ]
  });
};
