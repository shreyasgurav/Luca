## Nova — Neural Omni-View Assistant

An on-device macOS assistant that sees your screen, understands context, and helps across tasks. Nova captures, analyzes, chats, and remembers—combining multimodal AI with a refined desktop UX.

Nova stands for “Neural Omni-View Assistant”.

### Highlights
- Multimodal: screenshot capture + vision analysis + optional OCR
- Smart memory: vector embeddings, semantic retrieval, session context, decay/dedupe
- Real integrations: email Q&A via Gmail, nearby search via Google Places
- Desktop-native UX: floating overlay, compact/expanded chat, selection capture

---

## Quick Start

1) Server setup
```bash
cd Server
npm install
cp config.production.js config.js
# Edit config.js with your API keys
npm start
```

2) macOS app
- Open the Xcode project in this repo
- Build and run the macOS target
- Ensure the server is running on port 3000

3) Use Nova
- Click the floating overlay to ask a question
- Use the selection tool to capture part of the screen, or ask about “what’s on my screen” to auto-capture

---

## Features

### Screen understanding
- Selection overlay with pixel-accurate crop and toolbar actions (Send/Copy/Cancel)
- Full-screen capture that safely excludes Nova’s own UI from being captured
- Vision-based OCR optional path when needed

### Chat with context
- Conversational interface with compact and expanded modes
- Ambient context (local time, location where permitted)
- Response streaming-ready API design

### Memory and retrieval
- Vector memory with embeddings generated via server endpoint
- Semantic search with composite scoring (cosine similarity + importance + recency + keyword boosts)
- Session-aware context construction with token budgeting and decay system

### Integrations
- Gmail: OAuth flow, list recent emails, and answer questions grounded only in your inbox
- Places: Nearby search with distance and deep links to Maps

---

## Architecture

- macOS app (SwiftUI/AppKit)
  - ScreenCaptureKit-based capture, selection overlay, OCR via Vision
  - Floating overlay window for chat (compact/expanded modes)
  - Vector memory client with Firestore storage and local embedding cache

- Local server (Node.js)
  - Chat/images: forwards prompts and screenshots to OpenAI
  - Embeddings: generates normalized embeddings (with a mock fallback for offline/dev)
  - Memory extraction: LLM-assisted JSON extraction with robust fallback heuristics
  - Gmail integration: OAuth + read-only queries grounded in email content
  - Places search: Google Places Text Search with location bias

---

## API Endpoints (local server)

- POST `/api/analyze` — multipart image analysis (fields: `image`, `includeOCR`, `sessionId`, `promptContext`)
- POST `/api/chat` — chat with optional `promptContext` and `sessionId`
- POST `/api/memory/extract` — extract structured memories from content
- POST `/api/embedding` — generate numeric embedding for text
- GET  `/api/gmail/status|auth|callback|emails` — Gmail status and email access
- POST `/api/gmail/query` — answer a question using recent emails only
- GET  `/api/places/search` — text search (query, lat, lng, radius, open_now)

---

## Configuration

OpenAI and integrations are configured in `Server/config.js` (copied from `config.production.js`). Set:
- `OPENAI_API_KEY`, `OPENAI_MODEL`
- Optional storage (S3/R2)
- Gmail OAuth: client id/secret/redirect
- Google Places API key

Tip: Prefer environment variables or a local, untracked config. Don’t commit real keys.

---

## Security & Privacy

- Keep API keys out of version control; rotate any exposed keys immediately
- Restrict CORS in production and add rate-limiting/auth to server routes
- Provide user controls for memory retention and the ability to purge data
- Avoid capturing sensitive windows; Nova’s own window is excluded from capture by design

---

## Development

### Prereqs
- macOS with Xcode (for the app)
- Node 18+ (for the server)

### Scripts
```bash
# Server
cd Server && npm start

# Optional: production runner scripts may be included in the repo
```

---

## Roadmap
- Streaming UI for chat responses
- Vector DB backend for scalable similarity search
- Evaluation harness for retrieval and prompt changes
- Built-in rate limiting and auth middleware

---

## License
MIT

---

Made with care for a fast, focused macOS AI experience.
