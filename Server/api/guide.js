const { callLucaGuide } = require('../lib/openaiClient');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.statusCode = 405; return res.end('Method Not Allowed'); }
  try {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8')) || {};

    const imageUrl = body.image_url || null; // optional
    const imageBase64 = body.image_base64 || null; // optional alternative
    const ocrText = body.ocr_text || '';
    const goal = body.goal || '';
    const lastInstruction = body.lastInstruction || '';
    const history = body.history || [];

    let finalImageUrl = imageUrl;
    if (!finalImageUrl && imageBase64) {
      // Data URL inline transfer to model vision input
      finalImageUrl = `data:image/jpeg;base64,${imageBase64}`;
    }

    const reply = await callLucaGuide({ imageUrl: finalImageUrl, ocrText, goal, lastInstruction, history });

    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(reply));
  } catch (err) {
    console.error('Guide error:', err);
    res.statusCode = 500;
    res.end(JSON.stringify({ error: err.message || 'Guide failed' }));
  }
};
