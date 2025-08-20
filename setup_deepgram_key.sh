#!/bin/bash

echo "🎧 Deepgram API Key Setup for Nova"
echo "=================================="
echo ""

# Check if DeepgramConfig.swift exists
if [ ! -f "cheatingai/System/DeepgramConfig.swift" ]; then
    echo "❌ DeepgramConfig.swift not found!"
    echo "Please run this script from the project root directory."
    exit 1
fi

echo "🔑 To get your Deepgram API key:"
echo "1. Go to https://console.deepgram.com/"
echo "2. Sign in or create an account"
echo "3. Go to 'API Keys' section"
echo "4. Click 'Create a New API Key'"
echo "5. Name it 'Nova STT'"
echo "6. Copy the generated key"
echo ""

read -p "Enter your Deepgram API key: " api_key

if [ -z "$api_key" ]; then
    echo "❌ No API key provided. Setup cancelled."
    exit 1
fi

# Backup the original file
cp cheatingai/System/DeepgramConfig.swift cheatingai/System/DeepgramConfig.swift.backup

# Replace the placeholder with the actual key (only the return statement, not the environment variable)
sed -i '' "s/return \"YOUR_DEEPGRAM_API_KEY_HERE\"/return \"$api_key\"/g" cheatingai/System/DeepgramConfig.swift

echo ""
echo "✅ Deepgram API key configured successfully!"
echo "📝 Original file backed up as: cheatingai/System/DeepgramConfig.swift.backup"
echo ""
echo "🚀 You can now build and run Nova with Deepgram STT!"
echo "   The Listen button should work properly now."
echo ""
echo "💡 To test: Build and run the project, then click the Listen button."
echo "   You should see live transcription instead of configuration errors."
