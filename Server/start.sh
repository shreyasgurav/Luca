#!/bin/bash

echo "🚀 Starting CheatingAI Server..."

# Check if config.js exists
if [ ! -f "config.js" ]; then
    echo "❌ Error: config.js not found!"
    echo "Please create config.js with your OpenAI API key"
    exit 1
fi

# Check if API key is configured
if grep -q "your-openai-api-key-here" config.js; then
    echo "⚠️  Warning: OpenAI API key not configured in config.js"
    echo "Please edit config.js and add your actual API key"
    echo ""
    echo "Example:"
    echo "OPENAI_API_KEY: 'sk-your-actual-api-key-here'"
    echo ""
    read -p "Press Enter to continue anyway (server may not work properly)..."
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Start the server
echo "🌟 Starting server..."
node server.js
