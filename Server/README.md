Serverless proxy for Nova

Env vars:
- OPENAI_API_KEY (required)
- OPENAI_MODEL=o3-turbo (default)
- Optional storage (S3/R2): S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_ENDPOINT
  - If not provided, images are sent as data URLs directly to OpenAI (no storage needed)

Local run (Express-like):
```bash
node server.js
```

Endpoint:
- POST /api/analyze (multipart/form-data: image, sessionId, includeOCR, promptContext)

Response JSON:
```json
{ "assistant_text": "...", "structured": null, "openai_raw": {"...": "..."} }
```


