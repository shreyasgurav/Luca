function setCors(res, origin) {
  const allowed = process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',').map(o => o.trim().replace(/\/$/, '')) : [];
  const isAllowed = !origin || allowed.length === 0 || allowed.includes(origin.replace(/\/$/, ''));
  if (isAllowed && origin) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  } else {
    res.setHeader('Access-Control-Allow-Origin', '*');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key');
  res.setHeader('Access-Control-Max-Age', '86400');
}

function validateApiKey(req) {
  const raw = process.env.LUCA_API_KEYS || '';
  const keys = raw.split(',').map(k => k.trim()).filter(Boolean);
  if (keys.length === 0) return true; // no keys configured => allow
  const key = req.headers['x-api-key'] || (req.headers['authorization'] ? String(req.headers['authorization']).replace(/^Bearer\s+/i, '') : '');
  return keys.includes(key);
}

async function handleCorsAndAuth(req, res) {
  setCors(res, req.headers.origin);
  if (req.method === 'OPTIONS') {
    res.statusCode = 204; res.end();
    return false;
  }
  if (!validateApiKey(req)) {
    res.statusCode = 401;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Invalid or missing API key' }));
    return false;
  }
  return true;
}

module.exports = { handleCorsAndAuth, setCors, validateApiKey };
