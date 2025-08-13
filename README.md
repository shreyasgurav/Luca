# 🚀 CheatingAI - Production Ready!

An intelligent iOS app with screenshot analysis and AI assistance, now with **one-command setup** and **embedded configuration**.

## ✨ What's New

🎯 **Production Ready** - No more manual terminal setup!  
🔑 **Embedded API Keys** - OpenAI configuration built into the project  
🚀 **One-Command Setup** - Run `./setup.sh` and you're ready to go  
📱 **Direct Build & Run** - Open in Xcode and run immediately  

## 🚀 Quick Start (3 Steps)

### 1. Setup Everything
```bash
./setup.sh
```
This configures your OpenAI API key and installs all dependencies automatically.

### 2. Start Server
```bash
cd Server
./start.sh
```

### 3. Build & Run iOS App
- Open `cheatingai.xcodeproj` in Xcode
- Build and run the app
- It automatically connects to the local server

## 🔑 Getting OpenAI API Key

1. Go to [OpenAI Platform](https://platform.openai.com/api-keys)
2. Sign in or create an account
3. Click "Create new secret key"
4. Copy the key (starts with `sk-`)
5. The setup script will guide you to paste it

## 📱 Features

- **Screenshot Analysis** - Upload images for AI analysis
- **Chat Interface** - Interactive AI conversations
- **Memory System** - Context-aware responses
- **Global Hotkeys** - Quick access from anywhere
- **Vector Memory** - Intelligent context retention

## 🛠️ Technical Stack

- **iOS App**: SwiftUI, Core Data, Vision framework
- **Server**: Node.js, OpenAI API integration
- **AI Models**: GPT-4o-mini for optimal performance
- **Storage**: Local storage with optional S3/R2 integration

## 📁 Project Structure

```
cheatingai/
├── cheatingai/           # iOS app source
├── Server/               # Node.js backend
├── setup.sh             # One-command setup
├── PRODUCTION_SETUP.md  # Detailed setup guide
└── README.md            # This file
```

## 🔒 Security

- API keys are stored locally and never committed to version control
- CORS protection enabled
- Input validation and sanitization
- Secure API key management

## 🚨 Troubleshooting

- **Setup Issues**: Run `./setup.sh` again
- **Server Problems**: Check `Server/README.md`
- **iOS Issues**: Verify server is running on port 3000

## 📚 Documentation

- [Production Setup Guide](PRODUCTION_SETUP.md) - Complete setup instructions
- [Server Documentation](Server/README.md) - Backend details
- [iOS App Guide](cheatingai/README.md) - App development info

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🎉 Support

If you need help:
1. Check the troubleshooting guides
2. Review the documentation
3. Open an issue with detailed information

---

**Your CheatingAI app is now production-ready! 🎯**

No more manual terminal setup - just run `./setup.sh`, start the server, and build your iOS app directly in Xcode.


