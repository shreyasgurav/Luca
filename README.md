# Nova — Neural Omni-View Assistant

An on-device macOS assistant that sees your screen, understands context, and helps across tasks. Nova captures, analyzes, chats, and remembers—combining multimodal AI with a refined desktop UX.

Nova stands for "Neural Omni-View Assistant".

## 🎯 Professional Audio Capture & Transcription

Nova uses **Screen Recording permission** to capture system audio (YouTube, Zoom, music, etc.) automatically and **Deepgram STT** for high-quality real-time transcription.

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

### 🎤 High-Quality Transcription
- **Deepgram STT**: Professional-grade speech-to-text
- **Real-time processing**: Immediate transcription feedback
- **Smart deduplication**: Removes repetitive content automatically
- **Clean transcripts**: Organized by source (on-device vs server)

---

## Quick Start

1) Server setup
```bash
cd Server
npm install
cp config.production.js config.js
# Edit config.js with your API keys (OpenAI + Deepgram)
npm start
```

2) Deepgram STT setup (for audio transcription)
```bash
cd Server
./setup_deepgram.sh
# Follow the instructions to get your Deepgram API key
# Edit config.js with your Deepgram API key
```

3) macOS app
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
- **High-quality transcription**: Deepgram STT for accurate speech-to-text

### Audio Capture & Transcription
- **Automatic system audio detection** via Screen Recording permission
- **Real-time transcription** using Deepgram STT (primary) and Apple Speech (fallback)
- **Voice Activity Detection** for intelligent audio chunking
- **Audio quality validation** and preprocessing
- **Session-based storage** with local file management
- **Smart deduplication** removes repetitive content automatically
- **Clean transcript format** organized by transcription source

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
  - **Audio transcription: Deepgram STT for high-quality speech-to-text**
  - Places search: Google Places Text Search with location bias

---

## API Endpoints (local server)

- POST `/api/analyze` — multipart image analysis (fields: `image`, `includeOCR`, `sessionId`, `promptContext`)
- POST `/api/chat` — chat with optional `promptContext` and `sessionId`
- POST `/api/memory/extract` — extract structured memories from content
- POST `/api/embedding` — generate numeric embedding for text
- **WebSocket `/`** — real-time audio streaming and transcription
- GET  `/api/places/search` — text search (query, lat, lng, radius, open_now)

---

## Configuration

OpenAI and Deepgram integrations are configured in `Server/config.js` (copied from `config.production.js`). Set:
- `OPENAI_API_KEY`, `OPENAI_MODEL` - For chat and image analysis
- **`DEEPGRAM_API_KEY`** - For high-quality audio transcription
- Optional storage (S3/R2)

- Google Places API key

**Tip**: Prefer environment variables or a local, untracked config. Don't commit real keys.

## Audio Transcription Quality

### Deepgram STT (Primary)
- **Model**: Nova-2 (optimized for real-time transcription)
- **Features**: Automatic punctuation, smart formatting, noise reduction
- **Latency**: Real-time processing with minimal delay
- **Accuracy**: Professional-grade transcription quality

### Apple Speech (Fallback)
- **Use case**: When Deepgram is unavailable or for testing
- **Features**: On-device processing, privacy-focused
- **Latency**: Slightly higher due to on-device processing

### Transcript Organization
Transcripts are automatically organized by source:
- **ON-DEVICE TRANSCRIPTION**: Apple Speech results
- **SERVER TRANSCRIPTION (Deepgram STT)**: Deepgram STT results  
- **SESSION NOTES**: System-generated summaries and metadata

---

## Troubleshooting

### Audio Capture Issues
1. **No system audio detected**: Ensure Screen Recording permission is granted
2. **Poor transcription quality**: Check Deepgram API key configuration
3. **Repetitive content**: Deduplication automatically removes common phrases

### Server Issues
1. **Transcription not working**: Run `./setup_deepgram.sh` to configure API key
2. **Port conflicts**: Change `PORT` in config.js if 3000 is busy
3. **API rate limits**: Check your Deepgram usage limits

### Transcript Quality
- **Empty transcripts**: Usually indicates no speech detected or API key issues
- **Repetitive content**: Automatically filtered out by smart deduplication
- **Format issues**: Transcripts are automatically organized and cleaned
