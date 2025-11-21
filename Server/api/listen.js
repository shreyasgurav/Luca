const fetch = require('node-fetch');
const { handleCorsAndAuth } = require('./lib/auth');

// Session storage
const sessions = new Map();
const audioBuffers = new Map();

// WebSocket server will be initialized from server.js
let wss = null;

function initializeWebSocket(server) {
  const WebSocket = require('ws');
  wss = new WebSocket.Server({ 
    server,
    path: '/ws'
  });

  wss.on('connection', (ws, req) => {
    console.log('🎧 WebSocket connection established');
    
    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message);
        console.log('📨 Received WS message:', data.type, data.sessionId);
        
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
        console.error('❌ WebSocket message error:', error);
        ws.send(JSON.stringify({ error: 'Invalid message format' }));
      }
    });

    ws.on('close', () => {
      console.log('🔌 WebSocket connection closed');
      // Clean up any sessions associated with this websocket
      for (const [sessionId, session] of sessions.entries()) {
        if (session.ws === ws) {
          cleanupSession(sessionId);
          break;
        }
      }
    });

    ws.on('error', (error) => {
      console.error('❌ WebSocket error:', error);
    });
  });

  console.log('🎧 WebSocket server initialized on /ws');
  return wss;
}

async function handleWebSocketStart(ws, data) {
  const sessionId = data.sessionId || generateSessionId();
  
  const session = {
    ws,
    startTime: Date.now(),
    audioChunks: [],
    transcript: '',
    isActive: true,
    recentTranscripts: []
  };
  
  sessions.set(sessionId, session);
  audioBuffers.set(sessionId, []);
  
  console.log(`🎤 Started listen session: ${sessionId}`);
  
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
    
    // Store chunk
    const buffers = audioBuffers.get(sessionId) || [];
    buffers.push(audioBuffer);
    audioBuffers.set(sessionId, buffers);
    
    // Transcribe this chunk
    const transcriptText = await transcribeAudioBuffer(audioBuffer);
    
    if (transcriptText) {
      // Deduplicate and append to session transcript
      const deduplicatedText = deduplicateServerTranscript(transcriptText, session);
      if (deduplicatedText) {
        session.transcript += (session.transcript ? ' ' : '') + deduplicatedText;
        session.recentTranscripts.push(deduplicatedText);
        
        // Keep only recent transcripts (last 10)
        if (session.recentTranscripts.length > 10) {
          session.recentTranscripts.shift();
        }
      }
      
      // Send transcription update
      ws.send(JSON.stringify({
        type: 'transcription_update',
        sessionId,
        chunkIndex,
        text: deduplicatedText || '',
        fullTranscript: session.transcript
      }));
    }
    
    // Send chunk acknowledgment
    ws.send(JSON.stringify({
      type: 'chunk_acknowledged',
      sessionId,
      chunkIndex,
      status: 'processed'
    }));
    
  } catch (error) {
    console.error('❌ Audio chunk processing error:', error);
    ws.send(JSON.stringify({ 
      error: 'Failed to process audio chunk',
      sessionId,
      chunkIndex 
    }));
  }
}

async function handleWebSocketStop(ws, data) {
  const { sessionId } = data;
  const session = sessions.get(sessionId);
  
  if (!session) {
    ws.send(JSON.stringify({ error: 'Session not found' }));
    return;
  }
  
  session.isActive = false;
  const duration = Date.now() - session.startTime;
  const stats = {
    duration: `${Math.round(duration / 1000)}s`,
    chunks: session.audioChunks.length,
    transcript_length: session.transcript.length
  };
  
  console.log(`🛑 Stopped listen session: ${sessionId}`, stats);
  
  ws.send(JSON.stringify({
    type: 'session_completed',
    sessionId,
    transcript: session.transcript,
    stats
  }));
  
  // Clean up after a delay to allow client to receive final message
  setTimeout(() => cleanupSession(sessionId), 1000);
}

async function transcribeAudioBuffer(buffer) {
  const deepgramKey = process.env.DEEPGRAM_API_KEY;
  if (!deepgramKey) {
    console.warn('⚠️ DEEPGRAM_API_KEY not set, skipping transcription');
    return '';
  }

  try {
    const url = 'https://api.deepgram.com/v1/listen?model=nova-2&language=en&punctuate=true&diarize=false&smart_format=true&filler_words=false&utterances=false&paragraphs=false&channels=1&sample_rate=16000';
    
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Token ${deepgramKey}`,
        'Content-Type': 'audio/wav'
      },
      body: buffer
    });
    
    if (!response.ok) {
      console.error('❌ Deepgram API error:', response.status, await response.text());
      return '';
    }
    
    const result = await response.json();
    const transcript = result.results?.channels?.[0]?.alternatives?.[0]?.transcript || '';
    
    if (transcript) {
      console.log('🎯 Transcribed:', transcript.substring(0, 100) + (transcript.length > 100 ? '...' : ''));
    }
    
    return transcript;
  } catch (error) {
    console.error('❌ Transcription error:', error);
    return '';
  }
}

function deduplicateServerTranscript(currentText, session) {
  if (!currentText || !currentText.trim()) return '';
  
  const current = currentText.trim().toLowerCase();
  
  // Check against recent transcripts to avoid duplicates
  for (const recent of session.recentTranscripts) {
    if (recent.toLowerCase().includes(current) || current.includes(recent.toLowerCase())) {
      return ''; // Skip duplicate
    }
  }
  
  return currentText.trim();
}

function cleanupSession(sessionId) {
  sessions.delete(sessionId);
  audioBuffers.delete(sessionId);
  console.log(`🧹 Cleaned up session: ${sessionId}`);
}

function generateSessionId() {
  return 'listen_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

// HTTP fallback endpoints
module.exports = async function handler(req, res) {
  const ok = await handleCorsAndAuth(req, res);
  if (!ok) return;

  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;

  if (path === '/api/listen/start' && req.method === 'POST') {
    const sessionId = generateSessionId();
    const session = {
      ws: null, // HTTP mode
      startTime: Date.now(),
      audioChunks: [],
      transcript: '',
      isActive: true,
      recentTranscripts: []
    };
    
    sessions.set(sessionId, session);
    audioBuffers.set(sessionId, []);
    
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ sessionId }));
    return;
  }

  if (path === '/api/listen/chunk' && req.method === 'POST') {
    // Handle HTTP audio chunk upload (multipart or raw)
    const chunks = [];
    for await (const chunk of req) {
      chunks.push(chunk);
    }
    const body = Buffer.concat(chunks);
    
    const sessionId = url.searchParams.get('sessionId');
    const session = sessions.get(sessionId);
    
    if (!session || !session.isActive) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: 'Invalid or inactive session' }));
      return;
    }

    try {
      const transcriptText = await transcribeAudioBuffer(body);
      
      if (transcriptText) {
        const deduplicatedText = deduplicateServerTranscript(transcriptText, session);
        if (deduplicatedText) {
          session.transcript += (session.transcript ? ' ' : '') + deduplicatedText;
          session.recentTranscripts.push(deduplicatedText);
        }
      }
      
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ 
        status: 'processed',
        transcript: session.transcript 
      }));
    } catch (error) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: 'Processing failed' }));
    }
    return;
  }

  if (path === '/api/listen/stop' && req.method === 'POST') {
    const sessionId = url.searchParams.get('sessionId');
    const session = sessions.get(sessionId);
    
    if (!session) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: 'Session not found' }));
      return;
    }
    
    session.isActive = false;
    const duration = Date.now() - session.startTime;
    
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({
      transcript: session.transcript,
      duration: Math.round(duration / 1000),
      chunks: session.audioChunks.length
    }));
    
    setTimeout(() => cleanupSession(sessionId), 1000);
    return;
  }

  res.statusCode = 404;
  res.end(JSON.stringify({ error: 'Endpoint not found' }));
};

module.exports.initializeWebSocket = initializeWebSocket;
