#!/bin/bash

echo "🎯 CheatingAI Server Setup"
echo "=========================="
echo ""

# Check if config.js already exists
if [ -f "config.js" ]; then
    echo "✅ config.js already exists!"
    echo "Current configuration:"
    grep "OPENAI_API_KEY" config.js
    echo ""
    read -p "Do you want to reconfigure? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup complete! Run ./start.sh to start the server."
        exit 0
    fi
fi

# Copy production config if it doesn't exist
if [ ! -f "config.production.js" ]; then
    echo "❌ config.production.js not found!"
    echo "Please ensure you have the complete project files."
    exit 1
fi

# Create config.js from template
cp config.production.js config.js
echo "✅ Created config.js from template"

echo ""
echo "🔑 OpenAI API Key Setup"
echo "======================="
echo "You need to add your OpenAI API key to config.js"
echo ""

# Check if user has API key
read -p "Do you have an OpenAI API key? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Please edit config.js and replace 'sk-your-actual-openai-api-key-here'"
    echo "with your actual API key."
    echo ""
    echo "You can use any text editor:"
    echo "  - nano config.js"
    echo "  - vim config.js"
    echo "  - open config.js (macOS)"
    echo "  - code config.js (VS Code)"
    echo ""
    read -p "Press Enter when you've updated the API key..."
    
    # Verify the key was updated
    if grep -q "sk-your-actual-openai-api-key-here" config.js; then
        echo "⚠️  Warning: API key still appears to be the placeholder"
        echo "Please make sure you've updated config.js with your real API key"
    else
        echo "✅ API key appears to be configured!"
    fi
else
    echo "To get an OpenAI API key:"
    echo "1. Go to https://platform.openai.com/api-keys"
    echo "2. Sign in or create an account"
    echo "3. Click 'Create new secret key'"
    echo "4. Copy the key (starts with 'sk-')"
    echo "5. Edit config.js and paste it"
    echo ""
    echo "Then run this setup script again."
    exit 0
fi

echo ""
echo "📦 Installing Dependencies"
echo "=========================="
npm install

echo ""
echo "🚀 Setup Complete!"
echo "================"
echo "Your server is now configured and ready to run."
echo ""
echo "To start the server:"
echo "  ./start.sh"
echo ""
echo "To start manually:"
echo "  node server.js"
echo ""
echo "The iOS app will automatically connect to http://localhost:3000"
echo ""
echo "Happy coding! 🎉"
