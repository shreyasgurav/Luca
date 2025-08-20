const fs = require('fs');
const path = require('path');
const url = require('url');
const Busboy = require('busboy');
const WebSocket = require('ws');

// WebSocket server for real-time audio streaming
let wss = null;

// Session management
const sessions = new Map();
const audioBuffers = new Map();

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

// Initialize WebSocket server
function initializeWebSocket(server) {
  try {
    wss = new WebSocket.Server({ 
      server,
      path: '/ws' // Add specific path for WebSocket
    });
    
    console.log('🔌 WebSocket server initialized on /ws path');
    
    wss.on('connection', (ws, req) => {
      console.log('🔌 WebSocket connection established');
      
      ws.on('message', async (message) => {
        try {
          const data = JSON.parse(message);
          
          switch (data.type) {
            case 'start_session':
              await handleWebSocketStart(ws, data);
              break;
            case 'audio_chunk':
              await handleWebSocketAudioChunk(ws, data);
              break;
            case 'stop_session':
              await handleWebSocketStop(ws, data);
              break;
            default:
              ws.send(JSON.stringify({ error: 'Unknown message type' }));
          }
        } catch (error) {
          console.error('WebSocket message error:', error);
          ws.send(JSON.stringify({ error: error.message }));
        }
      });
      
      ws.on('close', () => {
        console.log('🔌 WebSocket connection closed');
      });
      
      ws.on('error', (error) => {
        console.error('WebSocket error:', error);
      });
    });
    
    wss.on('error', (error) => {
      console.error('WebSocket server error:', error);
    });
    
  } catch (error) {
    console.error('Failed to initialize WebSocket server:', error);
  }
}

async function handleWebSocketStart(ws, data) {
  const sessionId = data.sessionId || `${Date.now()}-${Math.random().toString(36).slice(2,8)}`;
  
  // Initialize session
  sessions.set(sessionId, {
    ws,
    startTime: Date.now(),
    audioChunks: [],
    transcript: '',
    isActive: true,
    recentTranscripts: [] // Add recentTranscripts to session
  });
  
  audioBuffers.set(sessionId, []);
  
  console.log(`🎬 WebSocket session started: ${sessionId}`);
  ws.send(JSON.stringify({ 
    type: 'session_started', 
    sessionId,
    status: 'ready'
  }));
}

async function handleWebSocketAudioChunk(ws, data) {
  const { sessionId, audioData, chunkIndex } = data;
  const session = sessions.get(sessionId);
  
  if (!session || !session.isActive) {
    ws.send(JSON.stringify({ error: 'Invalid or inactive session' }));
    return;
  }
  
  try {
    // Decode base64 audio data
    const audioBuffer = Buffer.from(audioData, 'base64');
    
    // Store chunk for processing
    session.audioChunks.push({
      index: chunkIndex,
      data: audioBuffer,
      timestamp: Date.now()
    });
    
    // Process audio chunk immediately for real-time transcription
    const transcript = await transcribeAudioBuffer(audioBuffer);
    
    if (transcript && transcript.trim()) {
      // ✅ FIX: Add server-side deduplication for repetitive content
      const cleanedTranscript = deduplicateServerTranscript(transcript, session);
      
      if (cleanedTranscript) {
        // Only add to session transcript if it's actual speech content
        session.transcript += (session.transcript ? '\n' : '') + cleanedTranscript;
        
        // Send immediate transcription back
        ws.send(JSON.stringify({
          type: 'transcription_update',
          sessionId,
          chunkIndex,
          text: cleanedTranscript,
          fullTranscript: session.transcript
        }));
        
        console.log(`📝 Accepted transcript: ${cleanedTranscript}`);
      } else {
        console.log(`🔍 Filtered duplicate transcript: ${transcript}`);
      }
    } else {
      // Log when no speech is detected (but don't add to transcript)
      console.log(`🔇 No speech detected in audio chunk ${chunkIndex}`);
    }
    
    // Acknowledge chunk received
    ws.send(JSON.stringify({
      type: 'chunk_acknowledged',
      sessionId,
      chunkIndex,
      status: 'processed'
    }));
    
  } catch (error) {
    console.error('Audio chunk processing error:', error);
    ws.send(JSON.stringify({ 
      error: 'Failed to process audio chunk',
      details: error.message 
    }));
  }
}

async function handleWebSocketStop(ws, data) {
  const { sessionId } = data;
  const session = sessions.get(sessionId);
  
  if (!session || !session.isActive) {
    ws.send(JSON.stringify({ error: 'Invalid or inactive session' }));
    return;
  }
  
  try {
    // Mark session as inactive
    session.isActive = false;
    
    // Calculate session duration
    const duration = Date.now() - session.startTime;
    const totalChunks = session.audioChunks.length;
    
    // Get only the actual speech transcript (filter out any system messages)
    const cleanTranscript = session.transcript.trim();
    
    // Send final session data
    ws.send(JSON.stringify({
      type: 'session_completed',
      sessionId,
      finalTranscript: cleanTranscript,
      duration,
      totalChunks,
      stats: {
        chunks: totalChunks,
        duration: Math.round(duration / 1000),
        transcriptLength: cleanTranscript.length
      }
    }));
    
    console.log(`✅ Session ${sessionId} completed: ${totalChunks} chunks, ${cleanTranscript.length} chars`);
    
    // Clean up session data
    sessions.delete(sessionId);
    
  } catch (error) {
    console.error('Session completion error:', error);
    ws.send(JSON.stringify({ 
      error: 'Failed to complete session',
      details: error.message 
    }));
  }
}

// HTTP endpoints for backward compatibility
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
    let cleanTranscript = '';
    
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
        if (text && text.trim()) {
          segments.push({ idx: i, file: files[i], text });
          cleanTranscript += (cleanTranscript ? '\n' : '') + text.trim();
        } else {
          segments.push({ idx: i, file: files[i], text: '', skipped: true, reason: 'no speech' });
        }
      } catch (e) {
        segments.push({ idx: i, file: files[i], text: '', error: e.message });
      }
    }

    // Only return transcript if we have actual speech content
    if (!cleanTranscript.trim()) {
      return sendJSON(res, 200, {
        success: true,
        sessionId,
        transcript: '',
        segments,
        stats: { chunks: files.length, bytes: totalBytes },
        message: 'No speech content detected in audio'
      });
    }
    
    return sendJSON(res, 200, {
      success: true,
      sessionId,
      transcript: cleanTranscript.trim(),
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

// ✅ FIX: Add server-side deduplication for repetitive content
function deduplicateServerTranscript(transcript, session) {
  if (!transcript || !transcript.trim()) {
    return null;
  }
  
  const cleanedTranscript = transcript.trim();
  
  // Check against recent transcripts in session
  if (session.recentTranscripts && session.recentTranscripts.length > 0) {
    for (const recent of session.recentTranscripts) {
      const similarity = calculateSimilarity(cleanedTranscript, recent);
      if (similarity > 0.8) { // 80% similar
        console.log(`🔍 Filtered duplicate transcript (similarity: ${similarity.toFixed(2)}): ${cleanedTranscript}`);
        return null;
      }
    }
  }
  
  // Check for repetitive content patterns
  if (isRepetitiveContent(cleanedTranscript)) {
    console.log(`🔍 Filtered repetitive content: ${cleanedTranscript}`);
    return null;
  }
  
  // Store recent transcript for future comparison
  if (!session.recentTranscripts) {
    session.recentTranscripts = [];
  }
  session.recentTranscripts.push(cleanedTranscript);
  
  // Keep only last 10 for memory efficiency
  if (session.recentTranscripts.length > 10) {
    session.recentTranscripts.shift();
  }
  
  return cleanedTranscript;
}

// ✅ NEW: Detect repetitive content patterns
function isRepetitiveContent(text) {
  const lowerText = text.toLowerCase();
  
  // Common repetitive phrases
  const repetitivePhrases = [
    'thank you for watching',
    'thanks for watching',
    'please like and subscribe',
    'don\'t forget to subscribe',
    'hit the like button',
    'comment below',
    'see you next time',
    'until next time',
    'goodbye',
    'bye',
    'end of video',
    'end of stream',
    'boom',
    'bzzz',
    'yeah yeah yeah',
    'ok ok ok',
    'right right right'
  ];
  
  // Check if text matches any repetitive phrase
  for (const phrase of repetitivePhrases) {
    if (lowerText.includes(phrase)) {
      return true;
    }
  }
  
  // Check for repeated words (e.g., "you you you")
  const words = lowerText.split(/\s+/).filter(word => word.length > 0);
  if (words.length >= 3) {
    for (let i = 0; i < words.length - 2; i++) {
      if (words[i] === words[i + 1] && words[i + 1] === words[i + 2]) {
        return true;
      }
    }
  }
  
  return false;
}

// ✅ NEW: Calculate simple character-based similarity
function calculateSimilarity(str1, str2) {
  const set1 = new Set(str1);
  const set2 = new Set(str2);
  const intersection = new Set([...set1].filter(x => set2.has(x)));
  const union = new Set([...set1, ...set2]);
  
  return union.size > 0 ? intersection.size / union.size : 0;
}

// New: Transcribe audio buffer directly using Deepgram STT
async function transcribeAudioBuffer(audioBuffer) {
  const deepgramApiKey = process.env.DEEPGRAM_API_KEY;
  if (!deepgramApiKey) {
    console.warn('No Deepgram API key found, skipping transcription');
    return '';
  }

  try {
    const FormData = require('form-data');
    const fetch = require('node-fetch');

    const form = new FormData();
    form.append('audio', audioBuffer, {
      filename: 'chunk.wav',
      contentType: 'audio/wav'
    });

    // Deepgram STT API with optimized settings for real-time transcription
    const resp = await fetch('https://api.deepgram.com/v1/listen?model=nova-2&language=en&punctuate=true&diarize=false&smart_format=true&filler_words=false&utterances=false&paragraphs=false&channels=1&sample_rate=16000', {
      method: 'POST',
      headers: { 
        'Authorization': `Token ${deepgramApiKey}`,
        'Content-Type': 'audio/wav'
      },
      body: audioBuffer
    });

    if (!resp.ok) {
      console.warn('Deepgram STT error:', resp.status);
      return '';
    }

    const data = await resp.json();
    const text = (data?.results?.channels?.[0]?.alternatives?.[0]?.transcript || '').trim();
    
    if (!text) {
      return '';
    }
    
    return text;
  } catch (e) {
    console.warn('Deepgram STT exception:', e.message);
    return '';
  }
}

async function transcribeWavFile(filePath) {
  const deepgramApiKey = process.env.DEEPGRAM_API_KEY;
  if (!deepgramApiKey) {
    console.warn('No Deepgram API key found, skipping transcription');
    return '';
  }

  try {
    const fs = require('fs');
    const audioBuffer = fs.readFileSync(filePath);
    
    const resp = await fetch('https://api.deepgram.com/v1/listen?model=nova-2&language=en&punctuate=true&diarize=false&smart_format=true&filler_words=false&utterances=false&paragraphs=false&channels=1&sample_rate=16000', {
      method: 'POST',
      headers: { 
        'Authorization': `Token ${deepgramApiKey}`,
        'Content-Type': 'audio/wav'
      },
      body: audioBuffer
    });

    if (!resp.ok) {
      console.warn('Deepgram STT error:', resp.status);
      return '';
    }

    const data = await resp.json();
    const text = (data?.results?.channels?.[0]?.alternatives?.[0]?.transcript || '').trim();
    
    if (!text) {
      return '';
    }
    
    return text;
  } catch (e) {
    console.warn('Deepgram STT exception:', e.message);
    return '';
  }
}

module.exports = async function handler(req, res) {
  const pathname = url.parse(req.url).pathname;
  if (pathname === '/api/listen/start' && req.method === 'POST') return handleStart(req, res);
  if (pathname === '/api/listen/chunk' && req.method === 'POST') return handleChunk(req, res);
  if (pathname === '/api/listen/stop' && req.method === 'POST') return handleStop(req, res);
  if (pathname === '/api/listen/query' && req.method === 'POST') return handleQuery(req, res);
  res.statusCode = 404; res.end('Not found');
};

// Export WebSocket initialization function
module.exports.initializeWebSocket = initializeWebSocket;
module.exports.sessions = sessions;


