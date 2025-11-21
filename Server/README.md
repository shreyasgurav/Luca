# Luca AI Server - Vercel Deployment

## 🚀 Quick Deploy

1. **Install Vercel CLI:**
   ```bash
   npm i -g vercel
   ```

2. **Deploy to Vercel:**
   ```bash
   cd Server
   vercel
   ```

## 🔑 Environment Variables Setup

**CRITICAL:** You must set these environment variables in your Vercel dashboard:

1. Go to [Vercel Dashboard](https://vercel.com/dashboard)
2. Select your Luca project
3. Go to **Settings** → **Environment Variables**
4. Add these variables:

### Required Variables:
```
OPENAI_API_KEY=sk-your-actual-openai-api-key-here
OPENAI_BASE=https://api.openai.com/v1
OPENAI_MODEL=gpt-4o-mini
```

### Optional Variables:
```
S3_BUCKET=your-bucket-name
S3_ACCESS_KEY_ID=your-access-key
S3_SECRET_ACCESS_KEY=your-secret-key
S3_REGION=your-region
S3_ENDPOINT=your-endpoint-url
```

## 🔧 How It Works

- **`/api/analyze`** → Routes to `api/analyze.js` (Real AI analysis)
- **`/api/chat`** → Routes to `api/chat.js` (Chat functionality)
- **`/api/embedding`** → Routes to `api/embedding.js` (Text embeddings)
- **`/api/memory`** → Routes to `api/memory.js` (Memory operations)
- **`/api/places`** → Routes to `api/places.js` (Location services)
- **Other `/api/*`** → Routes to `vercel-server.js` (Fallback/mock responses)

## 🐛 Troubleshooting

### "OpenAI API configured! Real image analysis coming soon."
This means the request is hitting the mock server instead of the real function.

**Check:**
1. Environment variables are set in Vercel dashboard
2. Vercel deployment is successful
3. Routes are properly configured

### Environment Variables Not Working
1. Ensure variables are set in Vercel dashboard (not in code)
2. Redeploy after setting environment variables
3. Check Vercel function logs for errors

## 📝 Deployment Commands

```bash
# Deploy to production
vercel --prod

# Deploy to preview
vercel

# View logs
vercel logs

# List deployments
vercel ls
```
