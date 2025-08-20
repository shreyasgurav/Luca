// Production configuration for CheatingAI
// Copy this file to config.js and replace with your actual API key

module.exports = {
  // OpenAI Configuration - REQUIRED
  OPENAI_API_KEY: 'sk-your-actual-openai-api-key-here', // Replace with your actual API key
  
  // OpenAI Settings - OPTIONAL (defaults are good for most users)
  OPENAI_BASE: 'https://api.openai.com/v1',
  OPENAI_MODEL: 'gpt-4o-mini',
  
  // Deepgram STT Configuration - REQUIRED for audio transcription
  DEEPGRAM_API_KEY: 'your-actual-deepgram-api-key-here', // Replace with your actual Deepgram API key
  
  // Server Configuration - OPTIONAL
  PORT: 3000,
  
  // Optional: S3/R2 Storage (leave empty for local storage)
  S3_BUCKET: '',
  S3_REGION: '',
  S3_ACCESS_KEY: '',
  S3_SECRET_KEY: '',
  
  // Memory System - OPTIONAL
  MEMORY_ENABLED: true,
  
  // Security - OPTIONAL
  CORS_ORIGIN: '*', // In production, restrict this to your app's domain
  RATE_LIMIT_ENABLED: false
};

/*
QUICK SETUP:
1. Copy this file to config.js
2. Replace 'sk-your-actual-openai-api-key-here' with your real OpenAI API key
3. Replace 'your-actual-deepgram-api-key-here' with your real Deepgram API key
4. Run ./start.sh to start the server
5. Build and run your iOS app

GETTING AN OPENAI API KEY:
1. Go to https://platform.openai.com/api-keys
2. Sign in or create an account
3. Click "Create new secret key"
4. Copy the key (starts with 'sk-')
5. Paste it in config.js

GETTING A DEEPGRAM API KEY:
1. Go to https://console.deepgram.com/
2. Sign in or create an account
3. Go to API Keys section
4. Create a new API key
5. Copy the key and paste it in config.js

SECURITY NOTES:
- Never commit your actual API keys to version control
- Add config.js to .gitignore
- Keep your API keys private and secure
*/
