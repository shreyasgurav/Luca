# 🚀 Quick Deploy Guide (2-3 Hours)

## Step 1: Deploy Firestore (15 min)
```bash
# From project root
firebase deploy --only firestore:indexes
firebase deploy --only firestore:rules

# Wait 5-15 min for indexes to build
# Check: Firebase Console → Firestore → Indexes
```

---

## Step 2: Vercel Environment Variables (10 min)

Go to: **Vercel Dashboard → Your Project → Settings → Environment Variables**

Add these (Production scope):
```bash
OPENAI_API_KEY=sk-proj-YOUR-KEY-HERE
OPENAI_MODEL=gpt-4o

# Get from Firebase Console → Project Settings
FIREBASE_API_KEY=AIzaSy...
FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_STORAGE_BUCKET=your-project.appspot.com
FIREBASE_MESSAGING_SENDER_ID=123456789
FIREBASE_APP_ID=1:123456789:web:abc123

NODE_ENV=production
```

**Then:** Click "Redeploy" on latest deployment

---

## Step 3: Update Client Code (5 min)

Edit: `Luca/System/AppConfig.swift`
```swift
static let serverBaseURL = "https://YOUR-APP.vercel.app"
// Change from: http://localhost:3000
```

**Find your URL:** Vercel Dashboard → Your Project → Production URL

---

## Step 4: Rebuild App (30 min)

In Xcode:
1. Product → Clean Build Folder (⌘⇧K)
2. Product → Archive
3. Distribute App → Copy App
4. Test the .app file locally

---

## Step 5: Test Production (15 min)

```bash
# Replace with your Vercel URL
export URL="https://your-app.vercel.app"

# Health check
curl $URL/api/health

# Memory test
curl -X POST $URL/api/memory \
  -H "Content-Type: application/json" \
  -d '{"content":"My name is John","userId":"test"}'

# Should return: {"extractedFacts":[...]} or []
```

If any return 404 or 500 → Check Vercel function logs

---

## Step 6: Enable Monitoring (20 min, optional)

1. **Sentry** (error tracking):
   - Go to sentry.io → Create account (free)
   - Create Node.js project
   - Copy DSN
   - Add to Vercel: `SENTRY_DSN=https://...@sentry.io/...`
   - Redeploy

2. **Set Billing Alerts**:
   - OpenAI: Set $50/month alert
   - Firebase: Enable Blaze plan if needed
   - Vercel: Monitor usage dashboard

---

## Step 7: Optional Cleanup (20 min)

**If you have existing duplicate memories:**
```bash
# Download Firebase service account JSON
# From: Firebase Console → Project Settings → Service Accounts
# Save as: firebase-service-account.json (project root)

cd Server/scripts
node consolidate-duplicates.js

# This will:
# - Find duplicate memories by contentHash
# - Merge metadata (importance, keywords, access count)
# - Delete duplicates
# - Keep most recent version
```

---

## ✅ Verification Checklist

Before launch, confirm:
- [ ] Firestore indexes show "Enabled" (not "Building")
- [ ] All Vercel env vars set (8+ variables)
- [ ] Client serverBaseURL points to Vercel (not localhost)
- [ ] Xcode build succeeded
- [ ] `/api/health` returns 200 OK
- [ ] `/api/memory` returns JSON (not 404)
- [ ] App connects to production server
- [ ] Test memory creation in app
- [ ] Test listen session in app
- [ ] Check Firestore for new data

---

## 🆘 If Something Breaks

### Memory 404 Errors
```bash
# Check Vercel deployment logs
# Verify route exists in vercel-server.js
```

### Permission Errors
```bash
# Verify Firestore rules deployed
firebase deploy --only firestore:rules

# Check in Firebase Console → Firestore → Rules
```

### Can't Read Segments
```bash
# Verify indexes built
# Firebase Console → Firestore → Indexes
# Wait if showing "Building"
```

### High OpenAI Costs
```bash
# Check if dedup is working
# Look for "🛑 Duplicate by content hash" in logs
# Run consolidate-duplicates.js
```

---

## 🎉 You're Done When...

1. App connects to production server
2. You can create a memory (say "My name is...")
3. You can start a listen session
4. Session saves to Firestore
5. No errors in Vercel logs
6. No permission errors in app logs

**Estimated Time:** 2-3 hours total

**Difficulty:** Medium (mostly copy-paste + waiting for deploys)

---

## 📊 Post-Launch Monitoring

**First 24 Hours:**
- Check Vercel dashboard every 4 hours
- Monitor OpenAI usage
- Watch Sentry for errors (if enabled)
- Check Firebase usage

**First Week:**
- Review Vercel analytics daily
- Check for duplicate memories in Firestore
- Monitor OpenAI costs
- Read user feedback

**After Week 1:**
- Weekly check-ins sufficient
- Set up automated alerts
- Review error trends monthly

---

## 💰 Expected Costs

**Vercel:** $0-20/month (free tier → Pro)
**OpenAI:** $20-100/month (depends on usage)
**Firebase:** $0-25/month (free tier → Blaze)
**Sentry:** $0/month (free tier)

**Total:** $20-145/month for small user base

---

## 🚀 Ready to Ship?

Follow steps 1-7 above → Launch! 

**Questions?** Check PRODUCTION_DEPLOYMENT.md for details
**Issues?** Check FIXES_APPLIED.md for what was fixed

