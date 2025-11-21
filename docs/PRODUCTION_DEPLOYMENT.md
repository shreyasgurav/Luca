# Production Deployment Checklist

## ✅ Code Changes Applied (DONE)

### Server Routes Fixed
- ✅ Unified `/api/memory` and `/api/memory/extract` to single endpoint
- ✅ Added `/api/embedding` route to server.js
- ✅ Updated vercel-server.js with all routes
- ✅ Added input validation (JSON parsing, required fields, length limits)
- ✅ Enhanced error responses with proper status codes

### Firestore Indexes Added
- ✅ `vector_memories` by `userId` + `contentHash` (for dedup)
- ✅ `segments` (collection group) by `userId` + `timestamp`
- ✅ `segments` (collection group) by `sessionId` + `timestamp`
- ✅ `user_sessions` by `userId` + `lastActivityAt`

### Memory System Fixes
- ✅ Client-side content hash dedup (before embedding cost)
- ✅ Pre-embedding semantic dedup at 88% threshold
- ✅ Smart merge logic with replacement detection
- ✅ Server-side stricter validation (10+ chars, 0.5+ importance)
- ✅ Centralized extraction with session cooldown

---

## 🔧 YOUR TASKS (MUST DO BEFORE PRODUCTION)

### 1. Environment Variables (CRITICAL)
Set these in Vercel project settings:

```bash
# OpenAI (REQUIRED)
OPENAI_API_KEY=sk-proj-xxxxx
OPENAI_MODEL=gpt-4o  # or your preferred model

# Firebase (REQUIRED - get from Firebase Console)
FIREBASE_API_KEY=AIzaSyxxxxx
FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_STORAGE_BUCKET=your-project.appspot.com
FIREBASE_MESSAGING_SENDER_ID=123456789
FIREBASE_APP_ID=1:123456789:web:xxxxx

# Optional (for production features)
SENTRY_DSN=https://xxxxx@sentry.io/xxxxx
REDIS_URL=redis://xxxxx  # if using Redis for rate limiting
NODE_ENV=production
```

**How to set in Vercel:**
1. Go to your Vercel project
2. Settings → Environment Variables
3. Add each variable
4. Redeploy

### 2. Deploy Firestore Indexes (CRITICAL)
```bash
# From your project root
firebase deploy --only firestore:indexes

# This will deploy the updated firestore.indexes.json
# Wait 5-15 minutes for indexes to build
```

**Verify indexes:**
1. Go to Firebase Console → Firestore → Indexes
2. Confirm all indexes show "Enabled" status
3. Check for any "Building" status and wait

### 3. Deploy Firestore Rules (CRITICAL)
```bash
firebase deploy --only firestore:rules

# This ensures your segments subcollection rules are live
```

**Test rules after deploy:**
- Try accessing segments from the app
- Check Firebase Console → Firestore → Rules → Playground
- Test read/write for `user_sessions/{id}/segments/{id}`

### 4. Update Client AppConfig (CRITICAL)

Edit `Luca/System/AppConfig.swift`:
```swift
struct AppConfig {
    // PRODUCTION - Update this to your Vercel URL
    static let serverBaseURL = "https://your-app.vercel.app"
    // NOT http://localhost:3000
    
    // Keep other config as is
}
```

**Find your Vercel URL:**
- Go to Vercel dashboard → Your project
- Copy the production URL (e.g., `luca-ai.vercel.app`)
- Use full HTTPS URL: `https://luca-ai.vercel.app`

### 5. Rebuild & Archive Xcode App
```bash
# In Xcode:
# 1. Product → Clean Build Folder (Cmd+Shift+K)
# 2. Product → Archive
# 3. Distribute App → Copy App
# 4. Test the .app file locally first
```

### 6. Enable Sentry Error Tracking (RECOMMENDED)

**Server setup:**
Edit `Server/lib/sentry.js` - already wired, just need DSN:
```javascript
// Will auto-activate when SENTRY_DSN env var is set
```

**Set in Vercel:**
1. Create account at sentry.io (free tier OK)
2. Create new project → Node.js
3. Copy DSN from Settings → Client Keys
4. Add to Vercel env: `SENTRY_DSN=https://xxxxx@sentry.io/xxxxx`
5. Redeploy

### 7. Test Production Endpoints (BEFORE GOING LIVE)

```bash
# Replace with your actual Vercel URL
export API_URL="https://your-app.vercel.app"

# Test health
curl $API_URL/api/health

# Test memory extraction (should return extracted facts or empty array)
curl -X POST $API_URL/api/memory \
  -H "Content-Type: application/json" \
  -d '{"content":"My name is John and I live in NYC","userId":"test-user-id"}'

# Test chat
curl -X POST $API_URL/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello","userId":"test-user-id"}'

# Test embedding
curl -X POST $API_URL/api/embedding \
  -H "Content-Type: application/json" \
  -d '{"text":"test text","userId":"test-user-id"}'
```

**Expected responses:**
- All should return 200 OK
- No 404 errors
- Memory returns `{ extractedFacts: [...] }`
- Chat returns `{ responseText: "..." }`
- Embedding returns `{ embedding: [0.123, ...] }`

### 8. Monitor First 24 Hours

**Check these metrics:**
- Vercel Functions dashboard → Invocations, errors, duration
- Firebase Console → Firestore → Usage (reads/writes)
- Sentry → Issues (if enabled)
- Check for "Missing permissions" errors in app logs

**Common issues to watch:**
- 404 on `/api/memory` → verify route deployment
- "Missing permissions" → check Firestore rules deployed
- Slow memory extraction → consider adding Redis caching
- High OpenAI costs → verify dedup is working

---

## 🚨 CRITICAL SECURITY CHECKS

### Before Launch:
- [ ] Changed `serverBaseURL` from localhost to production URL
- [ ] All API endpoints require authentication (handled by middleware)
- [ ] Firestore rules deployed and tested
- [ ] Rate limiting enabled (Redis or in-memory)
- [ ] No API keys in client code (only in server env vars)
- [ ] CORS configured to allow only your domain
- [ ] Sentry DSN set for error tracking

### Post-Launch Monitoring:
- [ ] Check Vercel usage dashboard daily for first week
- [ ] Monitor OpenAI API usage (set billing alerts)
- [ ] Watch Firebase usage (Firestore reads/writes)
- [ ] Review Sentry errors weekly
- [ ] Check for duplicate memories in Firestore console

---

## 📊 Expected Costs (Rough Estimates)

**Vercel (Free tier should cover light usage):**
- 100GB bandwidth/month
- 100k function invocations
- Upgrade to Pro ($20/mo) if you exceed

**OpenAI (Pay per use):**
- Memory extraction: ~$0.03 per conversation
- Chat: ~$0.01-0.05 per message (depends on model)
- Embeddings: ~$0.0001 per text
- **Set billing alert at $50/month**

**Firebase (Free tier generous):**
- 50k reads/day free
- 20k writes/day free
- Upgrade to Blaze (pay-as-you-go) when needed

---

## 🐛 Known Issues to Monitor

1. **Memory Duplication**
   - Fixed on new memories via contentHash
   - Existing duplicates may remain
   - Run consolidation script if needed (I can create this)

2. **Segment Permission Errors**
   - Fixed in rules
   - Old segments without userId may still error
   - Monitor logs for "Missing permissions" on segments

3. **Memory Extraction 404**
   - Fixed by unifying routes
   - Clear after redeployment
   - If persists, check Vercel function logs

---

## 🚀 Deployment Commands Summary

```bash
# 1. Deploy Firestore
firebase deploy --only firestore:indexes
firebase deploy --only firestore:rules

# 2. Update client code
# Edit Luca/System/AppConfig.swift with production URL

# 3. Build Xcode app
# Product → Archive in Xcode

# 4. Deploy server (Vercel auto-deploys from git)
git add .
git commit -m "Production ready"
git push origin main  # Or your deployment branch

# 5. Verify deployment
curl https://your-app.vercel.app/api/health
```

---

## 📞 Emergency Rollback Plan

If production breaks:
1. Revert last git commit: `git revert HEAD && git push`
2. Vercel auto-deploys the previous version
3. Or use Vercel dashboard → Deployments → Redeploy previous
4. Check Sentry for error details
5. Fix locally, test, redeploy

---

## ✅ Final Checklist Before Launch

- [ ] All environment variables set in Vercel
- [ ] Firestore indexes deployed and enabled
- [ ] Firestore rules deployed
- [ ] Client `AppConfig.swift` updated with production URL
- [ ] Xcode app archived and tested locally
- [ ] All production endpoints tested and returning 200
- [ ] Sentry configured for error tracking
- [ ] OpenAI billing alert set
- [ ] Firebase Blaze plan enabled (if needed)
- [ ] Monitoring dashboard bookmarked
- [ ] Rollback plan documented

**When all checked → YOU'RE PRODUCTION READY! 🎉**

