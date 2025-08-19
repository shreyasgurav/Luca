const fs = require('fs');
const FormData = require('form-data');
const fetch = require('node-fetch');

// Test the Whisper API directly
async function testWhisperAPI() {
    console.log('🧪 Testing Whisper API directly...');
    
    try {
        // Create a simple test audio file (silence for testing)
        const testAudioPath = './test_audio.wav';
        
        // Create a minimal WAV file (1 second of silence)
        const sampleRate = 16000;
        const duration = 1; // 1 second
        const samples = sampleRate * duration;
        
        // WAV header
        const buffer = Buffer.alloc(44 + samples * 2);
        let offset = 0;
        
        // RIFF header
        buffer.write('RIFF', offset); offset += 4;
        buffer.writeUInt32LE(36 + samples * 2, offset); offset += 4;
        buffer.write('WAVE', offset); offset += 4;
        
        // fmt chunk
        buffer.write('fmt ', offset); offset += 4;
        buffer.writeUInt32LE(16, offset); offset += 4; // fmt chunk size
        buffer.writeUInt16LE(1, offset); offset += 2;  // PCM format
        buffer.writeUInt16LE(1, offset); offset += 2;  // mono
        buffer.writeUInt32LE(sampleRate, offset); offset += 4; // sample rate
        buffer.writeUInt32LE(sampleRate * 2, offset); offset += 4; // byte rate
        buffer.writeUInt16LE(2, offset); offset += 2;  // block align
        buffer.writeUInt16LE(16, offset); offset += 2; // bits per sample
        
        // data chunk
        buffer.write('data', offset); offset += 4;
        buffer.writeUInt32LE(samples * 2, offset); offset += 4;
        
        // Write silence samples (Int16, little-endian)
        for (let i = 0; i < samples; i++) {
            buffer.writeInt16LE(0, offset + i * 2);
        }
        
        // Write the test file
        fs.writeFileSync(testAudioPath, buffer);
        console.log(`✅ Created test audio file: ${testAudioPath}`);
        
        // Test with OpenAI Whisper API
        const formData = new FormData();
        formData.append('file', fs.createReadStream(testAudioPath));
        formData.append('model', 'whisper-1');
        formData.append('language', 'en');
        
        console.log('📤 Sending to Whisper API...');
        
        const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${process.env.OPENAI_API_KEY || 'your-api-key-here'}`
            },
            body: formData
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            console.error(`❌ Whisper API error: ${response.status} ${response.statusText}`);
            console.error(`Error details: ${errorText}`);
            return;
        }
        
        const result = await response.json();
        console.log('✅ Whisper API response:');
        console.log(JSON.stringify(result, null, 2));
        
        // Clean up test file
        fs.unlinkSync(testAudioPath);
        console.log('🧹 Cleaned up test audio file');
        
    } catch (error) {
        console.error('❌ Error testing Whisper API:', error);
    }
}

// Test with a real audio file if available
async function testWithRealAudio() {
    console.log('\n🎵 Testing with real audio file if available...');
    
    const possibleAudioFiles = [
        './test_audio.wav',
        './audio_sample.wav',
        './sample.wav'
    ];
    
    for (const audioFile of possibleAudioFiles) {
        if (fs.existsSync(audioFile)) {
            console.log(`📁 Found audio file: ${audioFile}`);
            
            try {
                const formData = new FormData();
                formData.append('file', fs.createReadStream(audioFile));
                formData.append('model', 'whisper-1');
                formData.append('language', 'en');
                
                console.log('📤 Sending real audio to Whisper API...');
                
                const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${process.env.OPENAI_API_KEY || 'your-api-key-here'}`
                    },
                    body: formData
                });
                
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error(`❌ Whisper API error: ${response.status} ${response.statusText}`);
                    console.error(`Error details: ${errorText}`);
                    return;
                }
                
                const result = await response.json();
                console.log('✅ Whisper API response with real audio:');
                console.log(JSON.stringify(result, null, 2));
                
                return;
                
            } catch (error) {
                console.error(`❌ Error testing with ${audioFile}:`, error);
            }
        }
    }
    
    console.log('ℹ️ No real audio files found for testing');
}

// Run tests
async function runTests() {
    console.log('🚀 Starting Whisper API tests...\n');
    
    await testWhisperAPI();
    await testWithRealAudio();
    
    console.log('\n✨ Whisper API tests completed!');
}

// Check if API key is set
if (!process.env.OPENAI_API_KEY) {
    console.log('⚠️  OPENAI_API_KEY environment variable not set');
    console.log('💡 Set it with: export OPENAI_API_KEY="your-api-key-here"');
    console.log('💡 Or edit the script to include your API key directly');
}

runTests();
