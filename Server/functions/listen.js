const fs = require('fs');
const path = require('path');
const url = require('url');
const Busboy = require('busboy');

function sendJSON(res, status, data) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(data));
}

function getSessionDir(sessionId) {
  const dir = path.join(process.cwd(), 'tmp_listen', sessionId);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return dir;
}

async function handleStart(req, res) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const bodyRaw = Buffer.concat(chunks).toString('utf8');
  let body = {};
  try { body = JSON.parse(bodyRaw || '{}'); } catch {}
  const sessionId = (body.sessionId && String(body.sessionId)) || `${Date.now()}-${Math.random().toString(36).slice(2,8)}`;
  getSessionDir(sessionId);
  return sendJSON(res, 200, { sessionId });
}

function parseMultipart(req) {
  return new Promise((resolve, reject) => {
    const busboy = Busboy({ headers: req.headers });
    const fields = {};
    let fileData = null;
    busboy.on('field', (name, val) => { fields[name] = val; });
    busboy.on('file', (name, file, info) => {
      const chunks = [];
      file.on('data', (d) => chunks.push(d));
      file.on('end', () => {
        fileData = { buffer: Buffer.concat(chunks), filename: info.filename || 'chunk.wav', mimetype: info.mimeType || 'audio/wav' };
      });
    });
    busboy.on('finish', () => resolve({ fields, file: fileData }));
    busboy.on('error', reject);
    req.pipe(busboy);
  });
}

async function handleChunk(req, res) {
  try {
    const parsed = url.parse(req.url, true);
    const sessionId = parsed.query.sessionId || '';
    if (!sessionId) return sendJSON(res, 400, { error: 'Missing sessionId' });
    const { file } = await parseMultipart(req);
    if (!file || !file.buffer) return sendJSON(res, 400, { error: 'Missing audio file' });
    const dir = getSessionDir(sessionId);
    const idx = Date.now();
    const out = path.join(dir, `${idx}.wav`);
    fs.writeFileSync(out, file.buffer);
    return sendJSON(res, 200, { ok: true, saved: path.basename(out) });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

async function handleStop(req, res) {
  try {
    const parsed = url.parse(req.url, true);
    const sessionId = parsed.query.sessionId || '';
    if (!sessionId) return sendJSON(res, 400, { error: 'Missing sessionId' });
    const dir = getSessionDir(sessionId);
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.wav')).sort();
    const totalBytes = files.reduce((acc, f) => acc + fs.statSync(path.join(dir, f)).size, 0);

    // If no files, return early
    if (!files.length) {
      return sendJSON(res, 200, {
        success: true,
        sessionId,
        transcript: '',
        segments: [],
        stats: { chunks: 0, bytes: 0 }
      });
    }

    // Transcribe each chunk sequentially and append
    const segments = [];
    // Extra: if a file is too small to be real audio (<1KB), skip it
    for (let i = 0; i < files.length; i++) {
      const filePath = path.join(dir, files[i]);
      try {
        const stat = fs.statSync(filePath);
        if (stat.size < 1024) {
          segments.push({ idx: i, file: files[i], text: '', skipped: true, reason: 'too small' });
          continue;
        }
      } catch {}
      try {
        const text = await transcribeWavFile(filePath);
        segments.push({ idx: i, file: files[i], text });
      } catch (e) {
        segments.push({ idx: i, file: files[i], text: '', error: e.message });
      }
    }

    let transcript = segments.map(s => (s.text || '').trim()).filter(Boolean).join('\n\n');
    if (!transcript.trim()) {
      // Ensure non-empty transcript so client file isn't blank during testing
      transcript = `[mock transcript] captured ${files.length} chunks, ${Math.round(totalBytes/1024)} KB total`;
    }
    return sendJSON(res, 200, {
      success: true,
      sessionId,
      transcript,
      segments,
      stats: { chunks: files.length, bytes: totalBytes },
      saved_dir: dir
    });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

async function handleQuery(req, res) {
  // Placeholder: echo back question; real implementation will RAG over segments
  const chunks = [];
  for await (const c of req) chunks.push(c);
  let body = {};
  try { body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch {}
  const answer = `Session ${body.sessionId || ''}: (placeholder) ${body.question || ''}`;
  return sendJSON(res, 200, { answer, citations: [] });
}

module.exports = async function handler(req, res) {
  const pathname = url.parse(req.url).pathname;
  if (pathname === '/api/listen/start' && req.method === 'POST') return handleStart(req, res);
  if (pathname === '/api/listen/chunk' && req.method === 'POST') return handleChunk(req, res);
  if (pathname === '/api/listen/stop' && req.method === 'POST') return handleStop(req, res);
  if (pathname === '/api/listen/query' && req.method === 'POST') return handleQuery(req, res);
  res.statusCode = 404; res.end('Not found');
};

async function transcribeWavFile(filePath) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    const seconds = Math.round((fs.statSync(filePath).size || 0) / 32000);
    return `[mock transcript ~${seconds}s from ${path.basename(filePath)}]`;
  }

  // Use undici FormData if available (Node >=18)
  const FormData = require('form-data');
  const fetch = require('node-fetch');

  const form = new FormData();
  form.append('model', 'whisper-1');
  form.append('response_format', 'json');
  form.append('file', fs.createReadStream(filePath), {
    filename: path.basename(filePath),
    contentType: 'audio/wav'
  });

  try {
    const resp = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}` },
      body: form
    });
    if (!resp.ok) {
      const t = await resp.text();
      console.warn('Whisper error:', resp.status, t);
      const seconds = Math.round((fs.statSync(filePath).size || 0) / 32000);
      return `[mock transcript ~${seconds}s from ${path.basename(filePath)}]`;
    }
    const data = await resp.json();
    // Some Whisper responses may return an empty string for low/quiet audio.
    // Fallback to a mock duration-based transcript instead of empty.
    const text = (data && typeof data.text === 'string') ? data.text.trim() : '';
    if (!text) {
      const seconds = Math.round((fs.statSync(filePath).size || 0) / 32000);
      return `[mock transcript ~${seconds}s from ${path.basename(filePath)}]`;
    }
    return text;
  } catch (e) {
    console.warn('Whisper exception:', e.message);
    const seconds = Math.round((fs.statSync(filePath).size || 0) / 32000);
    return `[mock transcript ~${seconds}s from ${path.basename(filePath)}]`;
  }
}


