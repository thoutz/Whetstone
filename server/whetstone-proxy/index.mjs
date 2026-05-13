/**
 * Whetstone Groq proxy — OpenAI-compatible POST /v1/chat/completions
 *
 * Env:
 *   GROQ_API_KEY          (required) Groq secret
 *   WHETSTONE_APP_TOKEN   (optional) If set, require Authorization: Bearer <token> from clients
 *   PORT                  (optional) default 8787
 *   BIND                  (optional) default 127.0.0.1
 */
import http from "node:http";

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_KEY = process.env.GROQ_API_KEY || "";
const APP_TOKEN = process.env.WHETSTONE_APP_TOKEN || "";
const PORT = Number(process.env.PORT || 8787);
const BIND = process.env.BIND || "127.0.0.1";

function json(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "whetstone-proxy" }));
    return;
  }

  if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
    json(res, 404, { error: "Not found" });
    return;
  }

  if (!GROQ_KEY) {
    json(res, 500, { error: "Server misconfigured: GROQ_API_KEY missing" });
    return;
  }

  if (APP_TOKEN) {
    const auth = req.headers.authorization || "";
    if (auth !== `Bearer ${APP_TOKEN}`) {
      json(res, 401, { error: "Unauthorized" });
      return;
    }
  }

  let raw;
  try {
    raw = await readBody(req);
  } catch {
    json(res, 400, { error: "Bad body" });
    return;
  }

  let upstreamRes;
  try {
    upstreamRes = await fetch(GROQ_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${GROQ_KEY}`,
        "Content-Type": "application/json",
      },
      body: raw,
    });
  } catch (e) {
    json(res, 502, {
      error: "Groq upstream fetch failed",
      detail: String(e?.message || e),
    });
    return;
  }

  const text = await upstreamRes.text();
  res.writeHead(upstreamRes.status, {
    "Content-Type": upstreamRes.headers.get("content-type") || "application/json",
  });
  res.end(text);
});

server.listen(PORT, BIND, () => {
  console.log(`whetstone-proxy listening on http://${BIND}:${PORT}`);
});
