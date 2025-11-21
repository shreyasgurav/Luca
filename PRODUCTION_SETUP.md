# 🚀 CheatingAI Production Setup Guide

This guide will help you set up CheatingAI to run directly without manually setting environment variables in the terminal.

## 🎯 What We've Built

- **Embedded Configuration**: OpenAI API key is stored in the project
- **One-Command Setup**: Run `./setup.sh` to configure everything
- **Production Ready**: No more manual terminal setup required
- **Secure**: API keys are kept out of version control

## 🚀 Quick Start (3 Steps)

### 1. Run Setup Script
```bash
./setup.sh
```
This will:
- Create configuration files
- Guide you through adding your OpenAI API key
- Install all dependencies
- Set up everything automatically

### 2. Start Server
```bash
cd Server
./start.sh
```

### 3. Build & Run iOS App
- Open `cheatingai.xcodeproj` in Xcode
- Build and run the app
- It will automatically connect to the local server

## 🔑 Getting Your OpenAI API Key

1. Go to [OpenAI Platform](https://platform.openai.com/api-keys)
2. Sign in or create an account
3. Click "Create new secret key"
4. Copy the key (starts with `sk-`)
5. The setup script will guide you to paste it

## 📁 What Changed

### Before (Manual Setup)
```bash
# Terminal 1: Set environment variables
export OPENAI_API_KEY="sk-your-key"
cd Server && npm start

# Terminal 2: Run iOS app
# Build in Xcode
```

### After (Production Ready)
```bash
# One command setup
./setup.sh

# Start server
cd Server && ./start.sh

# Build and run iOS app directly
# No terminal setup needed!
```

## 🛠️ Technical Details

### Server Changes
- `config.js` - Stores API key and settings
- `config.production.js` - Template for production
- `start.sh` - Automated server startup
- `setup.sh` - Guided configuration

### Security Features
- `config.js` is in `.gitignore` (never committed)
- API keys are stored locally only
- CORS protection enabled
- Input validation and sanitization

### iOS App
- Automatically connects to `localhost:3000`
- No configuration changes needed
- Handles server connection automatically

## 🔒 Security Best Practices

1. **Never commit `config.js`** - It's already in `.gitignore`
2. **Keep API key private** - Don't share your config file
3. **Restrict CORS in production** - Edit `config.js` if needed
4. **Monitor API usage** - Check OpenAI dashboard regularly

## 🚨 Troubleshooting

### Setup Issues
```bash
# Re-run setup
./setup.sh

# Manual server setup
cd Server
./setup.sh
```

### Server Won't Start
- Check if port 3000 is available
- Verify `config.js` exists and has valid API key
- Run `./start.sh` for detailed error messages

### iOS App Can't Connect
- Ensure server is running on port 3000
- Check firewall settings
- Verify both are on same network

### API Errors
- Check OpenAI API key validity
- Ensure you have API credits
- Verify the model specified in config

## 📱 Distribution

### For Personal Use
- Everything is ready to go
- Run `./setup.sh` once, then use normally

### For Team Use
- Each developer runs `./setup.sh`
- Each gets their own `config.js`
- No shared API keys

### For Production Deployment
- Update `config.js` with production settings
- Consider using environment variables for cloud deployment
- Restrict CORS origins to your domain

## 🎉 Benefits

✅ **No more terminal setup** - Everything embedded  
✅ **One-command configuration** - Run `./setup.sh`  
✅ **Production ready** - Build and run directly  
✅ **Secure** - API keys protected from version control  
✅ **User friendly** - Guided setup process  
✅ **Maintainable** - Clear configuration structure  

## 📞 Support

If you encounter issues:
1. Check the server console for error messages
2. Verify your OpenAI API key is valid
3. Ensure all dependencies are installed
4. Check network connectivity
5. Review the troubleshooting section above

---

**Happy coding! 🎉**

Your CheatingAI app is now production-ready and can be built and run directly without any manual terminal setup.
