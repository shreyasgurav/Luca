#!/usr/bin/env node

/**
 * Test script for Deepgram STT integration
 * Run with: node test_deepgram.js
 */

const fs = require('fs');
const path = require('path');

// Load config
let config;
try {
  config = require('./config.js');
} catch (e) {
  console.log('❌ No config.js found. Please run: cp config.production.js config.js');
  process.exit(1);
}

if (!config.DEEPGRAM_API_KEY || config.DEEPGRAM_API_KEY === 'your-actual-deepgram-api-key-here') {
  console.log('❌ Deepgram API key not configured in config.js');
  console.log('Please edit config.js and add your Deepgram API key');
  process.exit(1);
}

console.log('✅ Deepgram API key found in config');
console.log('🔑 Key:', config.DEEPGRAM_API_KEY.substring(0, 10) + '...');

// Test Deepgram API connection
async function testDeepgramConnection() {
  try {
    const response = await fetch('https://api.deepgram.com/v1/listen', {
      method: 'POST',
      headers: {
        'Authorization': `Token ${config.DEEPGRAM_API_KEY}`,
        'Content-Type': 'audio/wav'
      },
      body: Buffer.from('dummy audio data') // This will fail but tests auth
    });
    
    if (response.status === 400) {
      // 400 is expected for invalid audio data, but means auth worked
      console.log('✅ Deepgram API connection successful (auth working)');
      return true;
    } else if (response.status === 401) {
      console.log('❌ Deepgram API authentication failed');
      return false;
    } else {
      console.log('✅ Deepgram API connection successful');
      return true;
    }
  } catch (error) {
    console.log('❌ Deepgram API connection failed:', error.message);
    return false;
  }
}

// Test with a real audio file if available
async function testWithAudioFile() {
  const testAudioPath = path.join(__dirname, 'tmp_listen', 'demo', 'test.wav');
  
  if (!fs.existsSync(testAudioPath)) {
    console.log('⚠️  No test audio file found at:', testAudioPath);
    console.log('   Create a test.wav file in Server/tmp_listen/demo/ to test transcription');
    return;
  }
  
  try {
    const audioBuffer = fs.readFileSync(testAudioPath);
    console.log('🎵 Testing with audio file:', testAudioPath);
    console.log('📊 File size:', (audioBuffer.length / 1024).toFixed(1), 'KB');
    
    const response = await fetch('https://api.deepgram.com/v1/listen?model=nova-2&language=en&punctuate=true&diarize=false&smart_format=true&filler_words=false&utterances=false&paragraphs=false&channels=1&sample_rate=16000', {
      method: 'POST',
      headers: {
        'Authorization': `Token ${config.DEEPGRAM_API_KEY}`,
        'Content-Type': 'audio/wav'
      },
      body: audioBuffer
    });
    
    if (response.ok) {
      const data = await response.json();
      const transcript = data?.results?.channels?.[0]?.alternatives?.[0]?.transcript || '';
      
      if (transcript) {
        console.log('✅ Transcription successful!');
        console.log('📝 Transcript:', transcript);
      } else {
        console.log('⚠️  Transcription returned empty result (may be silence/noise)');
      }
    } else {
      console.log('❌ Transcription failed:', response.status, response.statusText);
    }
  } catch (error) {
    console.log('❌ Transcription test failed:', error.message);
  }
}

// Main test
async function main() {
  console.log('🧪 Testing Deepgram STT Integration');
  console.log('==================================');
  console.log('');
  
  const authWorking = await testDeepgramConnection();
  
  if (authWorking) {
    console.log('');
    await testWithAudioFile();
  }
  
  console.log('');
  console.log('🎯 Next steps:');
  console.log('1. Start the server: npm start');
  console.log('2. Use the macOS app to test audio capture');
  console.log('3. Check transcripts in the SessionTranscripts folder');
}

main().catch(console.error);
