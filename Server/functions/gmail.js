const url = require('url');
const fs = require('fs');
const path = require('path');
const { google } = require('googleapis');
const config = require('../config');
const { callOpenAI } = require('../lib/openaiClient');

function getTokensFilePath() {
  const tokensPath = config.GMAIL_TOKENS_PATH || './gmail_tokens.json';
  if (path.isAbsolute(tokensPath)) return tokensPath;
  return path.join(__dirname, '..', tokensPath);
}

function loadTokens() {
  const p = getTokensFilePath();
  if (!fs.existsSync(p)) return null;
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

function saveTokens(tokens) {
  const p = getTokensFilePath();
  try {
    fs.writeFileSync(p, JSON.stringify(tokens, null, 2), 'utf8');
    return true;
  } catch (e) {
    console.error('Failed to save Gmail tokens:', e.message);
    return false;
  }
}

function getOAuth2Client() {
  const { GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REDIRECT_URI } = config;
  if (!GMAIL_CLIENT_ID || !GMAIL_CLIENT_SECRET || !GMAIL_REDIRECT_URI) {
    throw new Error('Gmail OAuth not configured. Set GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, and GMAIL_REDIRECT_URI in config or env.');
  }
  const oAuth2Client = new google.auth.OAuth2(
    GMAIL_CLIENT_ID,
    GMAIL_CLIENT_SECRET,
    GMAIL_REDIRECT_URI
  );
  const tokens = loadTokens();
  if (tokens) oAuth2Client.setCredentials(tokens);
  return oAuth2Client;
}

function isAuthed(oAuth2Client) {
  const tokens = oAuth2Client.credentials;
  return !!(tokens && (tokens.access_token || tokens.refresh_token));
}

function sendJSON(res, status, data) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(data));
}

async function handleAuthURL(req, res) {
  try {
    const oAuth2Client = getOAuth2Client();
    const scopes = [
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/userinfo.email'
    ];
    const parsed = url.parse(req.url, true);
    const loginHint = (parsed.query.email || '').trim();
    const authUrl = oAuth2Client.generateAuthUrl({
      access_type: 'offline',
      prompt: 'consent',
      scope: scopes,
      login_hint: loginHint || undefined
    });
    return sendJSON(res, 200, { auth_url: authUrl });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

async function handleCallback(req, res) {
  try {
    const oAuth2Client = getOAuth2Client();
    const parsed = url.parse(req.url, true);
    const code = parsed.query.code;
    if (!code) return sendJSON(res, 400, { error: 'Missing code' });
    const { tokens } = await oAuth2Client.getToken(code);
    oAuth2Client.setCredentials(tokens);
    saveTokens(tokens);
    return sendJSON(res, 200, { success: true, message: 'Gmail connected' });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

function base64UrlDecode(str) {
  if (!str) return '';
  // Gmail uses base64url
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const buff = Buffer.from(b64, 'base64');
  return buff.toString('utf8');
}

function extractPlainText(payload) {
  if (!payload) return '';
  if (payload.mimeType === 'text/plain' && payload.body && payload.body.data) {
    return base64UrlDecode(payload.body.data);
  }
  if (payload.parts && Array.isArray(payload.parts)) {
    // Prefer text/plain, fallback to text/html
    const plain = payload.parts.find(p => p.mimeType === 'text/plain');
    if (plain && plain.body && plain.body.data) return base64UrlDecode(plain.body.data);
    const html = payload.parts.find(p => p.mimeType === 'text/html');
    if (html && html.body && html.body.data) {
      const raw = base64UrlDecode(html.body.data);
      // Strip HTML tags very simply
      return raw.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    }
    // Nested parts
    for (const part of payload.parts) {
      const nested = extractPlainText(part);
      if (nested) return nested;
    }
  }
  if (payload.body && payload.body.data) return base64UrlDecode(payload.body.data);
  return '';
}

function headerValue(headers, name) {
  const h = headers?.find(h => h.name?.toLowerCase() === name.toLowerCase());
  return h?.value || '';
}

async function listRecentEmails(oAuth2Client, maxResults) {
  const gmail = google.gmail({ version: 'v1', auth: oAuth2Client });
  const listResp = await gmail.users.messages.list({ userId: 'me', maxResults: maxResults || 10 });
  const ids = (listResp.data.messages || []).map(m => m.id);
  const emails = [];
  for (const id of ids) {
    const msg = await gmail.users.messages.get({ userId: 'me', id, format: 'full' });
    const payload = msg.data.payload;
    const headers = payload?.headers || [];
    const subject = headerValue(headers, 'Subject');
    const from = headerValue(headers, 'From');
    const date = headerValue(headers, 'Date');
    const snippet = msg.data.snippet || '';
    const text = extractPlainText(payload);
    emails.push({ id, subject, from, date, snippet, text });
  }
  return emails;
}

async function handleListEmails(req, res) {
  try {
    const oAuth2Client = getOAuth2Client();
    if (!isAuthed(oAuth2Client)) {
      const scopes = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/userinfo.email'
      ];
      const authUrl = oAuth2Client.generateAuthUrl({ access_type: 'offline', prompt: 'consent', scope: scopes });
      return sendJSON(res, 401, { error: 'Not authorized', auth_url: authUrl });
    }
    const parsed = url.parse(req.url, true);
    const max = Math.min(parseInt(parsed.query.max || '5', 10) || 5, 25);
    const emails = await listRecentEmails(oAuth2Client, max);
    return sendJSON(res, 200, { emails });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks).toString('utf8');
  try { return JSON.parse(raw); } catch { return {}; }
}

async function handleQuery(req, res) {
  try {
    if (req.method !== 'POST') {
      res.statusCode = 405; return res.end('Method Not Allowed');
    }
    const oAuth2Client = getOAuth2Client();
    if (!isAuthed(oAuth2Client)) {
      const scopes = [
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/userinfo.email'
      ];
      const authUrl = oAuth2Client.generateAuthUrl({ access_type: 'offline', prompt: 'consent', scope: scopes });
      return sendJSON(res, 401, { error: 'Not authorized', auth_url: authUrl });
    }
    const body = await readJsonBody(req);
    const question = (body.question || '').trim();
    const maxEmails = Math.min(parseInt(body.maxEmails || 10, 10) || 10, 25);
    if (!question) return sendJSON(res, 400, { error: 'Missing question' });

    const emails = await listRecentEmails(oAuth2Client, maxEmails);
    const context = emails.map((e, i) => `Email ${i + 1}:
Subject: ${e.subject}
From: ${e.from}
Date: ${e.date}
Body: ${e.text?.slice(0, 4000) || ''}`).join('\n\n---\n\n');

    const prompt = `You are helping the user answer a question using ONLY the content of the following recent emails. Read them carefully.

Rules:
- If the answer is found, quote the relevant email briefly and give the exact answer.
- If uncertain or not found, say you could not find it in the checked emails.
- Be concise.

Question: ${question}

Emails:
${context}`;

    const result = await callOpenAI({ imageUrl: null, promptContext: prompt, includeOCR: false, sessionId: 'gmail-query' });
    const answer = (function extractAssistantText(openAIResponse) {
      try {
        if (openAIResponse.output && Array.isArray(openAIResponse.output)) {
          const messageOutput = openAIResponse.output.find(item => item.type === 'message');
          if (messageOutput && messageOutput.content && Array.isArray(messageOutput.content)) {
            const textContent = messageOutput.content.find(item => item.type === 'output_text');
            if (textContent && textContent.text) return textContent.text;
          }
        }
        return openAIResponse.output_text || openAIResponse.choices?.[0]?.message?.content || 'No response received';
      } catch { return 'Failed to parse response'; }
    })(result);

    return sendJSON(res, 200, { answer, checked_emails: emails.length });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

async function getAuthedEmail(oAuth2Client) {
  try {
    const oauth2 = google.oauth2({ version: 'v2', auth: oAuth2Client });
    const info = await oauth2.userinfo.get();
    return info?.data?.email || '';
  } catch {
    return '';
  }
}

async function handleStatus(req, res) {
  try {
    const oAuth2Client = getOAuth2Client();
    const connected = isAuthed(oAuth2Client);
    const email = connected ? await getAuthedEmail(oAuth2Client) : '';
    return sendJSON(res, 200, { connected, email });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

async function handleDisconnect(req, res) {
  try {
    if (req.method !== 'POST' && req.method !== 'GET') {
      res.statusCode = 405; return res.end('Method Not Allowed');
    }
    const p = getTokensFilePath();
    try { fs.unlinkSync(p); } catch {}
    return sendJSON(res, 200, { success: true, disconnected: true });
  } catch (e) {
    return sendJSON(res, 500, { error: e.message });
  }
}

module.exports = async function handler(req, res) {
  const pathname = url.parse(req.url).pathname;
  if (pathname === '/api/gmail/auth' && req.method === 'GET') return handleAuthURL(req, res);
  if (pathname === '/api/gmail/callback' && req.method === 'GET') return handleCallback(req, res);
  if (pathname === '/api/gmail/emails' && req.method === 'GET') return handleListEmails(req, res);
  if (pathname === '/api/gmail/status' && req.method === 'GET') return handleStatus(req, res);
  if (pathname === '/api/gmail/query') return handleQuery(req, res);
  if (pathname === '/api/gmail/disconnect') return handleDisconnect(req, res);
  res.statusCode = 404; res.end('Not found');
};


