// server.js — EPAM Learn × Claude Proxy Server
// Forwards requests from the Chrome extension to the Anthropic API.
// Your API key stays here on the server — never in the browser.

require("dotenv").config();
const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";

// ── Middleware ────────────────────────────────────────────────────────────────

// Only allow requests from the Chrome extension (and localhost for testing)
app.use(cors({
  origin: (origin, callback) => {
    const allowed = [
      /^chrome-extension:\/\//,   // any Chrome extension
      /^http:\/\/localhost/,       // local testing
      /^http:\/\/127\.0\.0\.1/,
    ];
    // Allow requests with no origin (e.g. curl)
    if (!origin || allowed.some((pattern) => pattern.test(origin))) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin '${origin}' not allowed`));
    }
  },
}));

app.use(express.json({ limit: "20mb" }));

// ── Health check ──────────────────────────────────────────────────────────────
app.get("/health", (_req, res) => {
  const hasKey = !!process.env.ANTHROPIC_API_KEY;
  res.json({
    status: "ok",
    apiKeyConfigured: hasKey,
    model: process.env.DEFAULT_MODEL || "claude-haiku-4-5",
  });
});

// ── Proxy endpoint ────────────────────────────────────────────────────────────
app.post("/api/claude", async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;

  if (!apiKey) {
    return res.status(500).json({
      error: "ANTHROPIC_API_KEY is not set. Add it to your .env file.",
    });
  }

  const { messages, systemPrompt, model } = req.body;

  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: "messages array is required." });
  }

  const body = {
    model: model || process.env.DEFAULT_MODEL || "claude-haiku-4-5",
    max_tokens: 1024,
    system: systemPrompt || "You are a helpful learning assistant.",
    messages,
  };

  try {
    const upstream = await fetch(ANTHROPIC_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });

    const data = await upstream.json();

    if (!upstream.ok) {
      console.error("[Anthropic error]", upstream.status, data);
      return res.status(upstream.status).json({ error: data?.error?.message || "Anthropic API error" });
    }

    const reply = data.content?.[0]?.text ?? "";
    res.json({ reply });

  } catch (err) {
    console.error("[Proxy error]", err.message);
    res.status(500).json({ error: `Proxy error: ${err.message}` });
  }
});

// ── YouTube transcript endpoint ───────────────────────────────────────────────
app.get("/api/youtube-transcript", async (req, res) => {
  const { videoId } = req.query;
  if (!videoId) return res.status(400).json({ error: "videoId is required" });

  try {
    // 1. Fetch the YouTube watch page to find the timedtext URL
    const pageRes = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
      headers: { "Accept-Language": "en-US,en;q=0.9", "User-Agent": "Mozilla/5.0" },
    });
    const html = await pageRes.text();

    // Extract captionTracks from ytInitialPlayerResponse
    const match = html.match(/"captionTracks":(\[.*?\])/);
    if (!match) return res.json({ transcript: null, reason: "no_captions" });

    const tracks = JSON.parse(match[1]);
    // Prefer English, fall back to first available
    const track =
      tracks.find((t) => t.languageCode === "en" && !t.kind) ||
      tracks.find((t) => t.languageCode === "en") ||
      tracks[0];

    if (!track?.baseUrl) return res.json({ transcript: null, reason: "no_track" });

    // 2. Fetch the XML transcript
    const xmlRes = await fetch(track.baseUrl);
    const xml = await xmlRes.text();

    // 3. Parse <text> tags into plain text
    const lines = [];
    const re = /<text[^>]*>([\s\S]*?)<\/text>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
      const text = m[1]
        .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
        .replace(/<[^>]+>/g, "").trim();
      if (text) lines.push(text);
    }

    const transcript = lines.join(" ");
    res.json({ transcript, language: track.languageCode });

  } catch (err) {
    console.error("[Transcript error]", err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Streaming endpoint ────────────────────────────────────────────────────────
app.post("/api/claude/stream", async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: "ANTHROPIC_API_KEY is not set." });
  }

  const { messages, systemPrompt, model, thinking } = req.body;
  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: "messages array is required." });
  }

  // SSE headers
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders();

  const selectedModel = model || process.env.DEFAULT_MODEL || "claude-sonnet-4-5";

  const body = {
    model: selectedModel,
    max_tokens: thinking ? 16000 : 2048,
    stream: true,
    system: systemPrompt || "You are a helpful learning assistant.",
    messages,
  };

  // Extended thinking (requires Sonnet or higher)
  if (thinking) {
    body.thinking = { type: "enabled", budget_tokens: 10000 };
  }

  try {
    const upstream = await fetch(ANTHROPIC_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });

    if (!upstream.ok) {
      const err = await upstream.json().catch(() => ({}));
      console.error("[Anthropic stream error]", upstream.status, err);
      res.write(`data: ${JSON.stringify({ error: err?.error?.message || "API error " + upstream.status })}\n\n`);
      res.end();
      return;
    }

    // Pipe SSE stream from Anthropic → client
    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) { res.end(); break; }
      res.write(decoder.decode(value, { stream: true }));
    }

  } catch (err) {
    console.error("[Stream proxy error]", err.message);
    res.write(`data: ${JSON.stringify({ error: `Proxy error: ${err.message}` })}\n\n`);
    res.end();
  }
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n✅  EPAM Learn × Claude proxy running at http://localhost:${PORT}`);
  console.log(`   Health check: http://localhost:${PORT}/health`);
  console.log(`   API endpoint: POST http://localhost:${PORT}/api/claude`);
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn("\n⚠️  ANTHROPIC_API_KEY is not set! Copy .env.example to .env and add your key.\n");
  }
});
