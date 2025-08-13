# CheatingAI Server

A production-ready Node.js server for the CheatingAI iOS app that handles OpenAI API calls and image analysis.

## 🚀 Quick Start (Production)

### 1. Setup Configuration
```bash
# Copy the production config template
cp config.production.js config.js

# Edit config.js and add your OpenAI API key
# Replace 'sk-your-actual-openai-api-key-here' with your real API key
```

### 2. Start Server
```bash
# Make startup script executable (first time only)
chmod +x start.sh

# Start the server
./start.sh
```

### 3. Build and Run iOS App
- Open the iOS project in Xcode
- Build and run the app
- The app will automatically connect to the local server

## 🔑 Getting OpenAI API Key

1. Go to [OpenAI Platform](https://platform.openai.com/api-keys)
2. Sign in or create an account
3. Click "Create new secret key"
4. Copy the key (starts with 'sk-')
5. Paste it in `config.js`

## 📁 File Structure

- `config.js` - Your configuration (create from config.production.js)
- `server.js` - Main server file
- `start.sh` - Production startup script
- `functions/` - API endpoint handlers
- `lib/` - Utility libraries

## ⚙️ Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| `OPENAI_API_KEY` | Your OpenAI API key | Required |
| `OPENAI_MODEL` | AI model to use | `gpt-4o-mini` |
| `PORT` | Server port | `3000` |
| `CORS_ORIGIN` | Allowed origins | `*` |

## 🔒 Security Notes

- **Never commit `config.js` to version control**
- The file is already in `.gitignore`
- Keep your API key private and secure
- Consider restricting `CORS_ORIGIN` in production

## 🛠️ Development

```bash
# Install dependencies
npm install

# Start server manually
node server.js

# Start with auto-restart (if nodemon installed)
npm run dev
```

## 📱 iOS App Integration

The iOS app automatically connects to `http://localhost:3000`. No additional configuration needed in the iOS project.

## 🚨 Troubleshooting

### Server won't start
- Check if `config.js` exists
- Verify your OpenAI API key is correct
- Ensure port 3000 is available

### API calls failing
- Verify the server is running
- Check OpenAI API key validity
- Ensure you have OpenAI API credits

### iOS app can't connect
- Verify server is running on port 3000
- Check firewall settings
- Ensure both are on same network

## 📞 Support

If you encounter issues:
1. Check the server console for error messages
2. Verify your OpenAI API key is valid
3. Ensure all dependencies are installed
4. Check network connectivity


