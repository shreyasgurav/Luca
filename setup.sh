#!/bin/bash

echo "🚀 CheatingAI Complete Setup"
echo "============================"
echo ""

# Check if we're in the right directory
if [ ! -d "Server" ] || [ ! -d "cheatingai" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    echo "Make sure you have both 'Server' and 'cheatingai' folders"
    exit 1
fi

echo "📱 Setting up CheatingAI iOS App + Server"
echo ""

# Navigate to Server directory and run setup
echo "🔧 Setting up Server..."
cd Server
./setup.sh
cd ..

echo ""
echo "🎯 Setup Summary"
echo "==============="
echo "✅ Server configured with OpenAI API key"
echo "✅ Dependencies installed"
echo "✅ iOS project ready to build"
echo ""
echo "🚀 Next Steps:"
echo "1. Start the server: cd Server && ./start.sh"
echo "2. Open cheatingai.xcodeproj in Xcode"
echo "3. Build and run the iOS app"
echo ""
echo "The app will automatically connect to the local server!"
echo ""
echo "Happy coding! 🎉"
