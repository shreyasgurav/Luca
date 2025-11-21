module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  return res.end(JSON.stringify({ status: 'ok', env: process.env.VERCEL ? 'Vercel' : 'Local', ts: Date.now() }));
}
