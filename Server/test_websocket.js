#!/usr/bin/env node

const WebSocket = require('ws');

console.log('🧪 Testing WebSocket Audio Streaming...\n');

// Test configuration
const WS_URL = 'ws://localhost:3000/ws';
const TEST_SESSION_ID = `test-${Date.now()}`;

// Create WebSocket connection
const ws = new WebSocket(WS_URL);

ws.on('open', function open() {
    console.log('✅ WebSocket connected');
    
    // Test 1: Start session
    console.log('\n🎬 Test 1: Starting session...');
    const startMessage = {
        type: 'start_session',
        sessionId: null
    };
    ws.send(JSON.stringify(startMessage));
});

ws.on('message', function message(data) {
    try {
        const response = JSON.parse(data.toString());
        console.log(`📨 Received: ${JSON.stringify(response, null, 2)}`);
        
        switch (response.type) {
            case 'session_started':
                console.log('✅ Session started successfully');
                
                // Test 2: Send audio chunk
                console.log('\n🎵 Test 2: Sending audio chunk...');
                const audioChunk = createTestAudioChunk();
                const chunkMessage = {
                    type: 'audio_chunk',
                    sessionId: response.sessionId,
                    audioData: audioChunk,
                    chunkIndex: 0
                };
                ws.send(JSON.stringify(chunkMessage));
                break;
                
            case 'transcription_update':
                console.log('✅ Transcription received');
                
                // Test 3: Send another chunk
                console.log('\n🎵 Test 3: Sending second audio chunk...');
                const audioChunk2 = createTestAudioChunk();
                const chunkMessage2 = {
                    type: 'audio_chunk',
                    sessionId: response.sessionId,
                    audioData: audioChunk2,
                    chunkIndex: 1
                };
                ws.send(JSON.stringify(chunkMessage2));
                break;
                
            case 'chunk_acknowledged':
                console.log(`✅ Chunk ${response.chunkIndex} acknowledged`);
                break;
                
            case 'session_completed':
                console.log('✅ Session completed successfully');
                console.log('\n🎉 All tests passed!');
                ws.close();
                break;
                
            case 'error':
                console.error(`❌ Error: ${response.error}`);
                ws.close();
                break;
                
            default:
                console.log(`⚠️ Unknown message type: ${response.type}`);
        }
    } catch (error) {
        console.error('❌ Failed to parse message:', error.message);
    }
});

ws.on('close', function close() {
    console.log('\n🔌 WebSocket connection closed');
    process.exit(0);
});

ws.on('error', function error(err) {
    console.error('❌ WebSocket error:', err.message);
    process.exit(1);
});

// Create a test audio chunk (1 second of silence)
function createTestAudioChunk() {
    const sampleRate = 16000;
    const duration = 1.0;
    const samples = new Int16Array(sampleRate * duration);
    
    // Convert to WAV format
    const wavData = createWAV(samples, sampleRate, 1);
    return wavData.toString('base64');
}

// Create WAV file from audio samples
function createWAV(samples, sampleRate, channels) {
    const bytesPerSample = 2;
    const dataSize = samples.length * bytesPerSample;
    const fileSize = 44 + dataSize;
    
    const buffer = Buffer.alloc(fileSize);
    let offset = 0;
    
    // RIFF header
    buffer.write('RIFF', offset); offset += 4;
    buffer.writeUInt32LE(fileSize - 8, offset); offset += 4;
    buffer.write('WAVE', offset); offset += 4;
    
    // Format chunk
    buffer.write('fmt ', offset); offset += 4;
    buffer.writeUInt32LE(16, offset); offset += 4;
    buffer.writeUInt16LE(1, offset); offset += 2; // PCM
    buffer.writeUInt16LE(channels, offset); offset += 2;
    buffer.writeUInt32LE(sampleRate, offset); offset += 4;
    buffer.writeUInt32LE(sampleRate * channels * bytesPerSample, offset); offset += 4;
    buffer.writeUInt16LE(channels * bytesPerSample, offset); offset += 2;
    buffer.writeUInt16LE(bytesPerSample * 8, offset); offset += 2;
    
    // Data chunk
    buffer.write('data', offset); offset += 4;
    buffer.writeUInt32LE(dataSize, offset); offset += 4;
    
    // Audio data
    for (let i = 0; i < samples.length; i++) {
        buffer.writeInt16LE(samples[i], offset);
        offset += 2;
    }
    
    return buffer;
}

// Handle process termination
process.on('SIGINT', function() {
    console.log('\n🛑 Test interrupted by user');
    ws.close();
    process.exit(0);
});

// Timeout after 30 seconds
setTimeout(() => {
    console.log('\n⏰ Test timeout - closing connection');
    ws.close();
    process.exit(1);
}, 30000);
