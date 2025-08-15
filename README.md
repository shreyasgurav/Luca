# Nova — Neural Omni-View Assistant

An on-device macOS assistant that sees your screen, understands context, and helps across tasks. Nova captures, analyzes, chats, and remembers—combining multimodal AI with a refined desktop UX.

Nova stands for "Neural Omni-View Assistant".

## 🎯 Professional Audio Capture

Nova uses **Screen Recording permission** to capture system audio (YouTube, Zoom, music, etc.) automatically. This is the same approach used by professional apps like Clueify.

### ✅ Zero Configuration Required
- **No external drivers** like BlackHole
- **No Audio MIDI Setup** configuration
- **No manual audio routing** changes
- **Just grant Screen Recording permission** and start using!

### 🔒 Permission Setup (One-time)
1. **First time you use Nova**, it will request Screen Recording permission
2. **Go to System Settings** → **Privacy & Security** → **Screen Recording**
3. **Enable permission for Nova**
4. **Restart Nova** and start listening!

### 🎧 What Gets Captured
- **System audio**: YouTube, Zoom, Spotify, any app audio
- **Screen content**: For context and analysis
- **Microphone**: If you speak while recording

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

## Features

### Highlights
- **Multimodal**: screenshot capture + vision analysis + optional OCR
- **Smart memory**: vector embeddings, semantic retrieval, session context, decay/dedupe
- **Real integrations**: nearby search via Google Places
- **Desktop-native UX**: floating overlay, compact/expanded chat, selection capture
- **Professional audio**: system audio capture via Screen Recording (no setup required)

### Audio Capture
- **Automatic system audio detection** via Screen Recording permission
- **Real-time transcription** using Apple Speech and OpenAI Whisper
- **Voice Activity Detection** for intelligent audio chunking
- **Audio quality validation** and preprocessing
- **Session-based storage** with local file management

### Memory System
- **Vector embeddings** for semantic search
- **Context-aware retrieval** based on current session
- **Automatic decay** and deduplication
- **Persistent storage** across app sessions

### UI/UX
- **Floating overlay** that stays on top
- **Compact/expanded chat** modes
- **Global keyboard shortcuts** (Cmd+Return, Cmd+Delete)
- **Modern chat interface** with dark themes
- **Responsive design** that adapts to content

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
  
  - Places search: Google Places Text Search with location bias

---

## API Endpoints (local server)

- POST `/api/analyze` — multipart image analysis (fields: `image`, `includeOCR`, `sessionId`, `promptContext`)
- POST `/api/chat` — chat with optional `promptContext` and `sessionId`
- POST `/api/memory/extract` — extract structured memories from content
- POST `/api/embedding` — generate numeric embedding for text

- GET  `/api/places/search` — text search (query, lat, lng, radius, open_now)

---

## Configuration

OpenAI and integrations are configured in `Server/config.js` (copied from `config.production.js`). Set:
- `OPENAI_API_KEY`, `OPENAI_MODEL`
- Optional storage (S3/R2)

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
