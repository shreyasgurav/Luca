Nova (macOS AI Assistant with Screen Capture)

Quick start
- Client (macOS): open Xcode, enable Screen Recording permission after first capture attempt.
- Server: cd Server && npm install && OPENAI_API_KEY=... S3_BUCKET=... npm start

Global hotkey: ⌘⇧Space to open selection overlay.

Endpoints
- POST /api/analyze (multipart: image, includeOCR, sessionId)
- POST /api/chat (json: { message, sessionId })

Testing
- Unit: `ScaleConverterTests` validates 2x scaling.


