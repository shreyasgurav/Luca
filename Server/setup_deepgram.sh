#!/bin/bash

echo "🎧 Deepgram STT Setup for Nova"
echo "=============================="
echo ""

# Check if config.js exists
if [ ! -f "config.js" ]; then
    echo "📝 Creating config.js from template..."
    cp config.production.js config.js
    echo "✅ Created config.js"
    echo ""
fi

# Check if DEEPGRAM_API_KEY is set
if grep -q "your-actual-deepgram-api-key-here" config.js; then
    echo "🔑 Deepgram API key not configured yet."
    echo ""
    echo "To get your Deepgram API key:"
    echo "1. Go to https://console.deepgram.com/"
    echo "2. Sign in or create an account"
    echo "3. Go to API Keys section"
    echo "4. Create a new API key"
    echo "5. Copy the key"
    echo ""
    echo "Then edit config.js and replace:"
    echo "  DEEPGRAM_API_KEY: 'your-actual-deepgram-api-key-here'"
    echo "with your actual API key."
    echo ""
    echo "Or set the environment variable:"
    echo "  export DEEPGRAM_API_KEY='your-key-here'"
    echo ""
else
    echo "✅ Deepgram API key is already configured in config.js"
fi

# Check environment variable
if [ -n "$DEEPGRAM_API_KEY" ]; then
    echo "✅ DEEPGRAM_API_KEY environment variable is set"
else
    echo "⚠️  DEEPGRAM_API_KEY environment variable is not set"
fi

echo ""
echo "🚀 To start the server with Deepgram STT:"
echo "  npm start"
echo ""
echo "📱 The macOS app will now use Deepgram for real-time transcription!"
