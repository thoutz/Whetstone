/**
 * Whetstone conversation REST API — scoped by Supabase JWT `sub`.
 *
 * Env (same file as Groq proxy: /etc/whetstone-proxy.env):
 *   DATABASE_URL          postgres://...
 *   SUPABASE_URL          https://<project-ref>.supabase.co — required for asymmetric user JWTs (ES256/RS256 via JWKS)
 *   SUPABASE_JWT_SECRET   Legacy shared secret — verifies HS256 tokens until fully migrated off signing-key rotation
 *   WHETSTONE_API_PORT    default 3001
 *   WHETSTONE_API_BIND    default 127.0.0.1
 *
 * After Supabase migrates to ECC/RSA signing keys, new access tokens use ES256/RS256; verify via JWKS:
 *   GET https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
 */
import http from "node:http";
import { URL } from "node:url";
import pg from "pg";
import { verifySupabaseAccessToken } from "../whetstone-shared/verify-supabase-access.mjs";

const PREFIX = "/whetstone/api";
const DATABASE_URL = process.env.DATABASE_URL || "";
const JWT_SECRET = process.env.SUPABASE_JWT_SECRET || "";
const SUPABASE_URL = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const PORT = Number(process.env.WHETSTONE_API_PORT || 3001);
const BIND = process.env.WHETSTONE_API_BIND || "127.0.0.1";

const pool = DATABASE_URL ? new pg.Pool({ connectionString: DATABASE_URL }) : null;

function json(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function noContent(res, status) {
  res.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
  });
  res.end();
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw.trim()) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}

async function listConversations(userId, res) {
  const { rows } = await pool.query(
    `SELECT id, title, total_tokens_used AS "total_tokens_used", created_at, updated_at
     FROM conversations WHERE user_id = $1::uuid
     ORDER BY updated_at DESC`,
    [userId]
  );
  json(res, 200, { conversations: rows });
}

async function getConversation(conversationId, userId, res) {
  const q = `
    SELECT id, title, total_tokens_used AS "total_tokens_used",
           api_history AS "api_history",
           created_at, updated_at,
           (
             SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.sort_order), '[]'::json)::json
             FROM (
               SELECT id, conversation_id AS "conversation_id", role,
                      content,
                      CASE WHEN payload IS NULL THEN NULL ELSE payload::json END AS payload,
                      sort_order AS "sort_order", created_at
               FROM messages
               WHERE conversation_id = c.id
             ) AS r
           ) AS messages
    FROM conversations AS c
    WHERE c.id = $1 AND c.user_id = $2
  `;
  const { rows } = await pool.query(q, [conversationId, userId]);
  if (!rows.length) return json(res, 404, { error: "Not found" });
  json(res, 200, { conversation: rows[0] });
}

async function createConversation(body, userId, res) {
  const id = body?.id;
  const title = (body?.title || "New conversation").toString().slice(0, 480);
  if (!id || typeof id !== "string") return json(res, 400, { error: "id (uuid) required" });
  await pool.query(
    `INSERT INTO conversations (id, user_id, title, total_tokens_used, api_history)
     VALUES ($1::uuid, $2::uuid, $3, 0, '[]'::jsonb)
     ON CONFLICT (id) DO NOTHING`,
    [id, userId, title]
  );
  await getConversation(id, userId, res);
}

async function patchConversation(conversationId, userId, body, res) {
  if (!body || typeof body !== "object") return json(res, 400, { error: "JSON body required" });
  const title = body.title != null ? String(body.title).slice(0, 480) : null;
  const total = body.total_tokens_used;
  const apiHistory = body.api_history;
  const uiMessages = body.ui_messages;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const ex = await client.query(
      `SELECT id FROM conversations WHERE id = $1::uuid AND user_id = $2::uuid`,
      [conversationId, userId]
    );
    if (!ex.rowCount) {
      await client.query("ROLLBACK");
      return json(res, 404, { error: "Not found" });
    }

    if (title != null) {
      await client.query(
        `UPDATE conversations SET title = $3, updated_at = now() WHERE id = $1::uuid AND user_id = $2::uuid`,
        [conversationId, userId, title]
      );
    }
    if (typeof total === "number" && Number.isFinite(total)) {
      await client.query(
        `UPDATE conversations SET total_tokens_used = $3, updated_at = now() WHERE id = $1::uuid AND user_id = $2::uuid`,
        [conversationId, userId, Math.max(0, Math.floor(total))]
      );
    }
    if (apiHistory !== undefined) {
      const jsonStr = JSON.stringify(apiHistory);
      await client.query(
        `UPDATE conversations SET api_history = $3::jsonb, updated_at = now() WHERE id = $1::uuid AND user_id = $2::uuid`,
        [conversationId, userId, jsonStr]
      );
    }

    if (Array.isArray(uiMessages)) {
      await client.query(`DELETE FROM messages WHERE conversation_id = $1::uuid`, [conversationId]);
      let ord = 0;
      for (const m of uiMessages) {
        const mid = m?.id;
        const role = m?.role;
        const content = m?.content ?? null;
        const payloadJson = m?.payload !== undefined ? JSON.stringify(m.payload) : null;
        if (!mid || !role) continue;
        await client.query(
          `INSERT INTO messages (id, conversation_id, role, content, payload, sort_order)
           VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb, $6)`,
          [mid, conversationId, role, content, payloadJson, ord++]
        );
      }
      await client.query(
        `UPDATE conversations SET updated_at = now() WHERE id = $1::uuid`,
        [conversationId]
      );
    }

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }

  await getConversation(conversationId, userId, res);
}

async function deleteConversation(conversationId, userId, res) {
  const { rowCount } = await pool.query(
    `DELETE FROM conversations WHERE id = $1::uuid AND user_id = $2::uuid`,
    [conversationId, userId]
  );
  if (!rowCount) return json(res, 404, { error: "Not found" });
  noContent(res, 204);
}

async function listMessages(conversationId, userId, res) {
  const chk = await pool.query(
    `SELECT 1 FROM conversations WHERE id = $1::uuid AND user_id = $2::uuid`,
    [conversationId, userId]
  );
  if (!chk.rowCount) return json(res, 404, { error: "Not found" });
  const { rows } = await pool.query(
    `SELECT id, role, content,
            CASE WHEN payload IS NULL THEN NULL ELSE payload::json END AS payload,
            sort_order AS "sort_order", created_at
     FROM messages
     WHERE conversation_id = $1::uuid
     ORDER BY sort_order ASC`,
    [conversationId]
  );
  json(res, 200, { messages: rows });
}

async function postMessage(conversationId, userId, body, res) {
  const chk = await pool.query(
    `SELECT 1 FROM conversations WHERE id = $1::uuid AND user_id = $2::uuid`,
    [conversationId, userId]
  );
  if (!chk.rowCount) return json(res, 404, { error: "Not found" });
  const mid = body?.id;
  const role = body?.role;
  const content = body?.content ?? null;
  const payloadArg = body?.payload !== undefined ? JSON.stringify(body.payload) : null;
  if (!mid || !role) return json(res, 400, { error: "id and role required" });
  const mx = await pool.query(
    `SELECT coalesce(max(sort_order), -1) + 1 AS n FROM messages WHERE conversation_id = $1::uuid`,
    [conversationId]
  );
  const sortOrder = mx.rows[0].n ?? 0;
  await pool.query(
    `INSERT INTO messages (id, conversation_id, role, content, payload, sort_order)
     VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb, $6)`,
    [mid, conversationId, role, content, payloadArg, sortOrder]
  );
  await pool.query(`UPDATE conversations SET updated_at = now() WHERE id = $1::uuid`, [
    conversationId,
  ]);
  json(res, 201, { ok: true });
}

async function handle(req, res) {
  if (!pool) return json(res, 500, { error: "DATABASE_URL missing" });
  if (!JWT_SECRET && !SUPABASE_URL) {
    return json(res, 500, {
      error:
        "Auth misconfigured: set SUPABASE_URL (JWKS for ES256/RS256 user tokens) and/or SUPABASE_JWT_SECRET (legacy HS256)",
    });
  }

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    });
    res.end();
    return;
  }

  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  const pathRaw = decodeURIComponent(url.pathname);

  /** No leading slashes — e.g. `conversations` or `conversations/<uuid>`. Matches verifyUserId scopes: JWT `sub` === Postgres `user_id`. */
  let tail;
  if (pathRaw === PREFIX || pathRaw.startsWith(`${PREFIX}/`)) {
    tail = pathRaw.slice(PREFIX.length).replace(/^\/+/, "");
  } else if (pathRaw === "/conversations" || pathRaw.startsWith("/conversations/")) {
    tail = pathRaw.replace(/^\/+/, "");
  } else {
    return json(res, 404, { error: "Not found" });
  }

  let userId;
  /** @type {string|null} */
  let sessionEmail = null;
  try {
    const sess = await verifySupabaseAccessToken(
      { SUPABASE_URL, SUPABASE_JWT_SECRET: JWT_SECRET },
      req.headers.authorization
    );
    userId = sess.sub;
    sessionEmail = sess.email;
  } catch {
    return json(res, 401, { error: "Unauthorized" });
  }

  if (req.method === "GET" && tail === "me") {
    return json(res, 200, { sub: userId, email: sessionEmail });
  }

  if (req.method === "GET" && tail === "conversations") {
    return await listConversations(userId, res);
  }

  if (req.method === "GET") {
    const m = /^conversations\/([0-9a-fA-F-]{36})$/.exec(tail);
    if (m) return await getConversation(m[1], userId, res);

    const m2 = /^conversations\/([0-9a-fA-F-]{36})\/messages$/.exec(tail);
    if (m2) return await listMessages(m2[1], userId, res);
    return json(res, 404, { error: "Not found" });
  }

  if (req.method === "POST") {
    if (tail === "conversations") {
      const body = await readJsonBody(req);
      return await createConversation(body, userId, res);
    }
    const pm = /^conversations\/([0-9a-fA-F-]{36})\/messages$/.exec(tail);
    if (pm) {
      const body = await readJsonBody(req);
      return await postMessage(pm[1], userId, body, res);
    }
    return json(res, 404, { error: "Not found" });
  }

  if (req.method === "PATCH") {
    const m = /^conversations\/([0-9a-fA-F-]{36})$/.exec(tail);
    if (m) {
      const body = await readJsonBody(req);
      if (body === undefined) return json(res, 400, { error: "Invalid JSON" });
      return await patchConversation(m[1], userId, body, res);
    }
    return json(res, 404, { error: "Not found" });
  }

  if (req.method === "DELETE") {
    const m = /^conversations\/([0-9a-fA-F-]{36})$/.exec(tail);
    if (m) return await deleteConversation(m[1], userId, res);
    return json(res, 404, { error: "Not found" });
  }

  return json(res, 405, { error: "Method not allowed" });
}

const server = http.createServer(async (req, res) => {
  let pathSafe = decodeURIComponent(new URL(req.url || "/", `http://${req.headers.host ?? "localhost"}`).pathname);
  if (req.method === "GET" && pathSafe === `${PREFIX}/health`) {
    return json(res, 200, { ok: true, service: "whetstone-api" });
  }

  try {
    await handle(req, res);
  } catch (e) {
    const name = e?.name || "";
    if (e.code === "auth" || name === "JsonWebTokenError" || name === "TokenExpiredError" || name === "NotBeforeError" || name === "JWTExpired") {
      return json(res, 401, { error: "Unauthorized" });
    }
    console.error(e);
    return json(res, 500, { error: String(e?.message || e) });
  }
});

server.listen(PORT, BIND, () => {
  console.log(`whetstone-api listening on http://${BIND}:${PORT}${PREFIX}`);
});
