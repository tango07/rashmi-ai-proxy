# 🍓 Rashmi AI — Proxy Server

> Local proxy server for the [Rashmi AI Chrome extension](https://github.com/tango07/rashmi-ai-extension). Forwards API requests to Anthropic server-side, bypassing browser CORS restrictions.

---

## Why do I need this?

If you see this error in the extension:

> ❌ *CORS requests are not allowed for this Organization because of its settings*

Your Anthropic account belongs to an organisation that blocks direct browser-to-Anthropic API calls. This proxy runs locally on your machine and makes the API calls server-side instead — no CORS restriction applies.

If you're using a **personal Anthropic account**, you don't need this proxy at all. Just paste your key directly in the extension settings.

---

## 🚀 Setup

### 1. Clone the repo

```bash
git clone https://github.com/tango07/rashmi-ai-proxy.git
cd rashmi-ai-proxy
```

### 2. Install dependencies

```bash
npm install
```

### 3. Configure your API key

```bash
cp .env.example .env
```

Open `.env` and fill in your Anthropic API key:

```
ANTHROPIC_API_KEY=sk-ant-your-key-here
DEFAULT_MODEL=claude-haiku-4-5
PORT=3001
```

> ⚠️ Never commit `.env` to git — it's already in `.gitignore`.

### 4. Start the server

```bash
npm start
```

You should see:
```
✅  Rashmi AI proxy running at http://localhost:3001
   Health check: http://localhost:3001/health
   API endpoint: POST http://localhost:3001/api/claude
```

### 5. Point the extension to the proxy

1. Open the Rashmi AI sidebar → click **⚙️**
2. Expand **Advanced (optional proxy)**
3. Set Proxy URL to `http://localhost:3001`
4. Click **Save Settings**

---

## 🔍 Verify it's working

```bash
curl http://localhost:3001/health
```

Expected response:
```json
{ "status": "ok", "apiKeyConfigured": true, "model": "claude-haiku-4-5" }
```

---

## ⚙️ Configuration

| Variable | Description | Default |
|---|---|---|
| `ANTHROPIC_API_KEY` | Your Anthropic API key (`sk-ant-...`) | required |
| `DEFAULT_MODEL` | Model used when the extension doesn't specify one | `claude-haiku-4-5` |
| `PORT` | Port the proxy listens on | `3001` |
| `OMDB_API_KEY` | (Optional) For Netflix IMDb ratings feature | — |

---

## 📡 API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Check proxy status and key configuration |
| `/api/claude` | POST | Single-turn Claude request |
| `/api/claude/stream` | POST | Streaming Claude request (SSE) |
| `/api/youtube-transcript` | GET | Fetch YouTube video transcript |
| `/api/pdf-text` | GET | Extract text from a PDF URL |
| `/api/imdb-rating` | GET | Fetch IMDb rating for a title |

---

## 🔒 Security

- Your API key lives only in `.env` on your machine — never in the browser or the extension
- The proxy only accepts requests from Chrome extensions and localhost (CORS policy)
- `.env` is gitignored — it will never be accidentally committed

