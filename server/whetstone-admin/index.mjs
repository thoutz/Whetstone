/**
 * Whetstone admin API — email/password login, JWT, Postgres management.
 *
 * Env (typically /etc/whetstone-proxy.env):
 *   DATABASE_URL           postgres://… (same DB as whetstone-api)
 *   ADMIN_EMAIL            e.g. thoutz@gmail.com
 *   ADMIN_PASSWORD         long random string
 *   ADMIN_JWT_SECRET       HS256 signing secret (32+ random bytes recommended)
 *   ADMIN_CORS_ORIGINS     optional, comma-separated (default: projectwhetstone.net + www)
 *   SUPABASE_URL           same host as other Whetstone services (for optional user lookups)
 *   SUPABASE_JWT_SECRET    optional HS256 fallback when verifying Supabase access tokens at auth/supabase-exchange
 *   SUPABASE_SERVICE_ROLE_KEY optional — if set, list/detail conversations include
 *                            user_email + user_display_name from GoTrue admin user API
 *   WHETSTONE_ADMIN_PORT   default 3002
 *   WHETSTONE_ADMIN_BIND   default 127.0.0.1
 *   ADMIN_DF_PATH          optional path for `df -k` host volume hint (default "/")
 */
import http from "node:http";
import crypto from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { URL } from "node:url";
import * as jose from "jose";
import pg from "pg";
import { verifySupabaseAccessToken } from "../whetstone-shared/verify-supabase-access.mjs";

const execFileAsync = promisify(execFile);

const PREFIX = "/admin/api";
const DATABASE_URL = process.env.DATABASE_URL || "";
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || "").trim().toLowerCase();
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "";
const ADMIN_JWT_SECRET = new TextEncoder().encode(process.env.ADMIN_JWT_SECRET || "");
const PORT = Number(process.env.WHETSTONE_ADMIN_PORT || 3002);
const BIND = process.env.WHETSTONE_ADMIN_BIND || "127.0.0.1";
const ADMIN_DF_PATH = (process.env.ADMIN_DF_PATH || "/").trim() || "/";

const DEFAULT_ORIGINS = "https://projectwhetstone.net,https://www.projectwhetstone.net";
const ALLOWED_ORIGINS = (process.env.ADMIN_CORS_ORIGINS || DEFAULT_ORIGINS)
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const pool = DATABASE_URL ? new pg.Pool({ connectionString: DATABASE_URL }) : null;

const SUPABASE_URL = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const SUPABASE_SERVICE_ROLE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
const SUPABASE_JWT_SECRET = (process.env.SUPABASE_JWT_SECRET || "").trim();

/** @type {Map<string, { display_name: string|null, email: string|null, cachedAt: number }>} */
const userProfileCache = new Map();
const USER_CACHE_TTL_MS = 15 * 60 * 1000;

function displayNameFromAuthUser(u) {
  if (!u || typeof u !== "object") return null;
  const meta = u.user_metadata || u.raw_user_meta_data || {};
  let full =
    (typeof meta.full_name === "string" && meta.full_name.trim()) ||
    (typeof meta.name === "string" && meta.name.trim()) ||
    [meta.first_name, meta.last_name]
      .filter((x) => typeof x === "string" && x.trim())
      .join(" ")
      .trim() ||
    (typeof meta.display_name === "string" && meta.display_name.trim());
  if (!full && Array.isArray(u.identities)) {
    for (const id of u.identities) {
      const d = id.identity_data || {};
      const guess =
        (typeof d.full_name === "string" && d.full_name.trim()) ||
        [d.first_name, d.last_name]
          .filter((x) => typeof x === "string" && x.trim())
          .join(" ")
          .trim();
      if (guess) {
        full = guess;
        break;
      }
    }
  }
  return full || null;
}

async function fetchSupabaseUserProfile(userId) {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return null;
  const now = Date.now();
  const hit = userProfileCache.get(userId);
  if (hit && now - hit.cachedAt < USER_CACHE_TTL_MS) {
    return { display_name: hit.display_name, email: hit.email };
  }
  try {
    const url = `${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`;
    const r = await fetch(url, {
      headers: {
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        apikey: SUPABASE_SERVICE_ROLE_KEY,
      },
    });
    if (!r.ok) {
      userProfileCache.set(userId, { display_name: null, email: null, cachedAt: now });
      return { display_name: null, email: null };
    }
    const raw = await r.json();
    const u = raw.user ?? raw;
    const email = typeof u.email === "string" && u.email.trim() ? u.email.trim() : null;
    const display_name = displayNameFromAuthUser(u);
    const row = { display_name, email, cachedAt: now };
    userProfileCache.set(userId, row);
    return { display_name, email };
  } catch (e) {
    console.error("supabase admin user fetch", userId, e?.message || e);
    userProfileCache.set(userId, { display_name: null, email: null, cachedAt: now });
    return { display_name: null, email: null };
  }
}

async function attachUserProfilesToConversations(rows) {
  if (!rows?.length || !SUPABASE_SERVICE_ROLE_KEY) {
    for (const r of rows || []) {
      r.user_display_name = null;
      r.user_email = null;
    }
    return;
  }
  const ids = [...new Set(rows.map((r) => r.user_id).filter(Boolean))];
  await Promise.all(ids.map((id) => fetchSupabaseUserProfile(String(id))));
  for (const r of rows) {
    const cached = userProfileCache.get(String(r.user_id));
    r.user_display_name = cached?.display_name ?? null;
    r.user_email = cached?.email ?? null;
  }
}

function corsForRequest(req) {
  const origin = req.headers.origin;
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    return {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
      "Vary": "Origin",
    };
  }
  return {};
}

function json(res, status, obj, req) {
  const body = JSON.stringify(obj);
  const h = {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
    ...corsForRequest(req),
  };
  res.writeHead(status, h);
  res.end(body);
}

function noContent(res, status, req) {
  res.writeHead(status, {
    ...corsForRequest(req),
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

function timingSafeEq(a, b) {
  try {
    const x = Buffer.from(String(a), "utf8");
    const y = Buffer.from(String(b), "utf8");
    if (x.length !== y.length) {
      crypto.timingSafeEqual(x, x);
      return false;
    }
    return crypto.timingSafeEqual(x, y);
  } catch {
    return false;
  }
}

async function signAdminToken(email) {
  if (!ADMIN_JWT_SECRET.length) throw new Error("ADMIN_JWT_SECRET missing");
  return await new jose.SignJWT({ role: "admin" })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(`admin:${email}`)
    .setIssuedAt()
    .setExpirationTime("8h")
    .sign(ADMIN_JWT_SECRET);
}

async function verifyAdminToken(authHeader, req, res) {
  const m = /^Bearer\s+(.+)$/i.exec(authHeader || "");
  if (!m) return null;
  if (!ADMIN_JWT_SECRET.length) {
    json(res, 500, { error: "ADMIN_JWT_SECRET missing" }, req);
    return false;
  }
  try {
    const { payload } = await jose.jwtVerify(m[1].trim(), ADMIN_JWT_SECRET, {
      algorithms: ["HS256"],
      clockTolerance: "30s",
    });
    if (payload.role !== "admin") return null;
    return payload;
  } catch {
    return null;
  }
}

async function statsHandler(req, res) {
  const [conv, msgs, tok, distinct, rows] = await Promise.all([
    pool.query(`SELECT COUNT(*)::int AS n FROM conversations`),
    pool.query(`SELECT COUNT(*)::int AS n FROM messages`),
    pool.query(`SELECT COALESCE(SUM(total_tokens_used), 0)::bigint AS n FROM conversations`),
    pool.query(`SELECT COUNT(DISTINCT user_id)::int AS n FROM conversations`),
    pool.query(`
      SELECT (m.created_at AT TIME ZONE 'UTC')::date AS day, COUNT(*)::int AS count
      FROM messages m
      WHERE m.created_at >= NOW() - INTERVAL '10 days'
      GROUP BY 1
      ORDER BY 1
    `),
  ]);

  const byDay = new Map();
  for (const r of rows.rows) {
    const d = r.day instanceof Date ? r.day.toISOString().slice(0, 10) : String(r.day).slice(0, 10);
    byDay.set(d, r.count);
  }
  const messages_by_day = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setUTCDate(d.getUTCDate() - i);
    const key = d.toISOString().slice(0, 10);
    messages_by_day.push({ day: key, count: byDay.get(key) || 0 });
  }

  json(
    res,
    200,
    {
      conversation_count: conv.rows[0]?.n ?? 0,
      message_count: msgs.rows[0]?.n ?? 0,
      total_tokens: Number(tok.rows[0]?.n ?? 0),
      distinct_users: distinct.rows[0]?.n ?? 0,
      messages_by_day,
    },
    req
  );
}

async function dfHostHint(pathArg) {
  try {
    const { stdout } = await execFileAsync("df", ["-k", pathArg], {
      timeout: 4000,
      maxBuffer: 64 * 1024,
    });
    const lines = stdout.trim().split("\n").filter(Boolean);
    if (lines.length < 2) return null;
    const cols = lines[1].trim().split(/\s+/);
    const totalKb = parseInt(cols[1], 10);
    const usedKb = parseInt(cols[2], 10);
    const availKb = parseInt(cols[3], 10);
    if (!Number.isFinite(totalKb) || totalKb <= 0) return null;
    const total_bytes = totalKb * 1024;
    let used_bytes = usedKb * 1024;
    if (used_bytes > total_bytes) used_bytes = total_bytes;
    let avail_bytes = availKb * 1024;
    if (avail_bytes < 0) avail_bytes = 0;
    const pctFromDf = cols[4]?.replace("%", "").trim();
    let use_percent = pctFromDf ? Number.parseFloat(pctFromDf) : NaN;
    if (!Number.isFinite(use_percent))
      use_percent = total_bytes ? Math.round((100 * used_bytes) / total_bytes) : 0;
    use_percent = Math.max(0, Math.min(100, Math.round(use_percent)));
    const mountLabel = cols.length >= 9 ? cols.slice(8).join(" ").trim() : cols[cols.length - 1] || pathArg;

    return {
      path_arg: pathArg,
      mount: mountLabel || pathArg,
      total_bytes,
      used_bytes,
      avail_bytes,
      use_percent,
    };
  } catch {
    return null;
  }
}

async function storageHandler(req, res) {
  const [dbRow, tableRows, host] = await Promise.all([
    pool.query(`
      SELECT
        current_database() AS name,
        pg_database_size(current_database())::bigint AS bytes,
        pg_size_pretty(pg_database_size(current_database())) AS size_pretty
    `),
    pool.query(`
      SELECT
        n.nspname AS schema,
        c.relname AS table,
        pg_total_relation_size(c.oid)::bigint AS total_bytes,
        pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty,
        pg_relation_size(c.oid)::bigint AS table_bytes,
        pg_indexes_size(c.oid)::bigint AS index_bytes
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'r'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
        AND n.nspname NOT LIKE 'pg_toast%'
      ORDER BY pg_total_relation_size(c.oid) DESC
      LIMIT 24
    `),
    dfHostHint(ADMIN_DF_PATH),
  ]);

  const database = {
    name: dbRow.rows[0]?.name ?? null,
    bytes: Number(dbRow.rows[0]?.bytes ?? 0),
    size_pretty: dbRow.rows[0]?.size_pretty ?? null,
  };

  const tables = tableRows.rows.map((r) => ({
    schema: r.schema,
    table: r.table,
    total_bytes: Number(r.total_bytes ?? 0),
    total_pretty: r.total_pretty,
    table_bytes: Number(r.table_bytes ?? 0),
    index_bytes: Number(r.index_bytes ?? 0),
  }));

  const tableSumBytes = tables.reduce((s, t) => s + (t.total_bytes || 0), 0);

  json(
    res,
    200,
    {
      database,
      tables,
      table_sum_bytes: tableSumBytes,
      host_volume: host,
      df_path: ADMIN_DF_PATH,
      note:
        "Database size reflects this connection's database logical size on disk inside Postgres (includes WAL/OS cache behavior not shown here). Host volume comes from POSIX `df -k` at ADMIN_DF_PATH and usually does not map 1:1 to the Postgres data directory unless you pick that mount.",
      collected_at: new Date().toISOString(),
    },
    req
  );
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;

function parseIsoDate(s) {
  if (!s || typeof s !== "string") return null;
  const t = Date.parse(s);
  if (Number.isNaN(t)) return null;
  return new Date(t).toISOString();
}

function buildConversationFilter(url) {
  const sp = url.searchParams;
  const qTitle = (sp.get("q") || "").trim();
  const uidPart = (sp.get("user_id_part") || "").trim();
  const userIdExact = (sp.get("user_id") || "").trim();
  const msgQ = (sp.get("message_contains") || "").trim();
  const updatedAfter = parseIsoDate(sp.get("updated_after") || "");
  const updatedBefore = parseIsoDate(sp.get("updated_before") || "");
  const minTok = sp.get("min_tokens");
  const maxTok = sp.get("max_tokens");
  const sort = (sp.get("sort") || "updated_desc").trim().toLowerCase();

  const cond = [];
  const vals = [];
  let n = 1;

  if (qTitle) {
    cond.push(`title ILIKE '%' || $${n++}::text || '%'`);
    vals.push(qTitle);
  }
  if (uidPart) {
    cond.push(`user_id::text ILIKE '%' || $${n++}::text || '%'`);
    vals.push(uidPart);
  }
  if (userIdExact) {
    if (!UUID_RE.test(userIdExact)) {
      return { error: "user_id must be a valid UUID" };
    }
    cond.push(`user_id = $${n++}::uuid`);
    vals.push(userIdExact);
  }
  if (msgQ) {
    cond.push(
      `EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = conversations.id AND m.content ILIKE '%' || $${n++}::text || '%')`
    );
    vals.push(msgQ);
  }
  if (updatedAfter) {
    cond.push(`updated_at >= $${n++}::timestamptz`);
    vals.push(updatedAfter);
  }
  if (updatedBefore) {
    cond.push(`updated_at <= $${n++}::timestamptz`);
    vals.push(updatedBefore);
  }
  if (minTok !== null && minTok !== undefined && String(minTok).trim() !== "") {
    const v = parseInt(String(minTok), 10);
    if (Number.isFinite(v)) {
      cond.push(`total_tokens_used >= $${n++}::int`);
      vals.push(v);
    }
  }
  if (maxTok !== null && maxTok !== undefined && String(maxTok).trim() !== "") {
    const v = parseInt(String(maxTok), 10);
    if (Number.isFinite(v)) {
      cond.push(`total_tokens_used <= $${n++}::int`);
      vals.push(v);
    }
  }

  const orderMap = {
    updated_desc: "updated_at DESC",
    updated_asc: "updated_at ASC",
    created_desc: "created_at DESC",
    created_asc: "created_at ASC",
    tokens_desc: "total_tokens_used DESC",
    tokens_asc: "total_tokens_used ASC",
  };
  const orderBy = orderMap[sort] || orderMap.updated_desc;

  const whereSql = cond.length ? `WHERE ${cond.join(" AND ")}` : "";
  return { whereSql, vals, orderBy };
}

async function listConversations(url, req, res) {
  const page = Math.max(1, parseInt(url.searchParams.get("page") || "1", 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get("limit") || "25", 10) || 25));
  const offset = (page - 1) * limit;

  const built = buildConversationFilter(url);
  if (built.error) return json(res, 400, { error: built.error }, req);

  const { whereSql, vals, orderBy } = built;
  const limitPlaceholder = vals.length + 1;
  const offsetPlaceholder = vals.length + 2;

  const listSql = `
    SELECT id, user_id, title, total_tokens_used AS "total_tokens_used", created_at, updated_at
    FROM conversations
    ${whereSql}
    ORDER BY ${orderBy}
    LIMIT $${limitPlaceholder}::int OFFSET $${offsetPlaceholder}::int
  `;
  const countSql = `SELECT COUNT(*)::int AS n FROM conversations ${whereSql}`;

  const listParams = [...vals, limit, offset];
  const countParams = [...vals];

  const [cr, lr] = await Promise.all([pool.query(countSql, countParams), pool.query(listSql, listParams)]);

  await attachUserProfilesToConversations(lr.rows);

  json(
    res,
    200,
    {
      conversations: lr.rows,
      total: cr.rows[0]?.n ?? 0,
      page,
      limit,
      user_profiles_enabled: Boolean(SUPABASE_SERVICE_ROLE_KEY && SUPABASE_URL),
    },
    req
  );
}

async function getConversation(id, req, res) {
  const q = `
    SELECT id, user_id, title, total_tokens_used AS "total_tokens_used",
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
    WHERE c.id = $1::uuid
  `;
  const { rows } = await pool.query(q, [id]);
  if (!rows.length) return json(res, 404, { error: "Not found" }, req);
  await attachUserProfilesToConversations(rows);
  json(res, 200, { conversation: rows[0] }, req);
}

async function patchConversation(id, body, req, res) {
  if (!body || typeof body !== "object") return json(res, 400, { error: "JSON body required" }, req);
  const title = body.title != null ? String(body.title).slice(0, 480) : null;
  if (title == null) return json(res, 400, { error: "title required" }, req);
  const { rowCount } = await pool.query(
    `UPDATE conversations SET title = $2, updated_at = now() WHERE id = $1::uuid`,
    [id, title]
  );
  if (!rowCount) return json(res, 404, { error: "Not found" }, req);
  await getConversation(id, req, res);
}

async function deleteConversation(id, req, res) {
  const { rowCount } = await pool.query(`DELETE FROM conversations WHERE id = $1::uuid`, [id]);
  if (!rowCount) return json(res, 404, { error: "Not found" }, req);
  noContent(res, 204, req);
}

async function sqlHandler(body, req, res) {
  const sql = (body?.sql ?? "").toString().trim();
  if (!sql) return json(res, 400, { error: "sql required" }, req);

  const client = await pool.connect();
  try {
    const r = await client.query(sql);

    // SELECT-ish: fields present
    if (r.rows && typeof r.rows === "object" && r.fields) {
      const columns = r.fields.map((f) => f.name);
      const sliced = r.rows.slice(0, 5000);
      const rows = sliced.map((row) => columns.map((c) => transformCell(row[c])));
      return json(res, 200, { columns, rows }, req);
    }
    json(res, 200, { note: `${r.command || "OK"} — ${r.rowCount ?? 0} row(s)`, rowCount: r.rowCount ?? 0 }, req);
  } catch (e) {
    json(res, 400, { error: String(e?.message || e) }, req);
  } finally {
    client.release();
  }
}

function transformCell(v) {
  if (v == null) return null;
  if (v instanceof Date) return v.toISOString();
  if (typeof v === "object") return JSON.stringify(v);
  return v;
}

async function loginHandler(body, req, res) {
  if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
    return json(res, 500, { error: "ADMIN_EMAIL / ADMIN_PASSWORD not configured" }, req);
  }
  const email = (body?.email || "").trim().toLowerCase();
  const password = String(body?.password ?? "");
  if (!email || !password) return json(res, 400, { error: "email and password required" }, req);

  if (email !== ADMIN_EMAIL || !timingSafeEq(password, ADMIN_PASSWORD)) {
    return json(res, 401, { error: "Invalid credentials" }, req);
  }

  const token = await signAdminToken(email);
  json(res, 200, { token, email }, req);
}

async function supabaseExchangeHandler(req, res) {
  if (!ADMIN_EMAIL) return json(res, 500, { error: "ADMIN_EMAIL not configured" }, req);
  if (!(SUPABASE_URL || SUPABASE_JWT_SECRET)) {
    return json(res, 500, { error: "SUPABASE_URL or SUPABASE_JWT_SECRET missing for JWT verification" }, req);
  }
  try {
    const { email } = await verifySupabaseAccessToken(
      { SUPABASE_URL, SUPABASE_JWT_SECRET },
      req.headers.authorization
    );
    if (!email || email !== ADMIN_EMAIL) {
      return json(res, 403, { error: "Forbidden" }, req);
    }
    const token = await signAdminToken(ADMIN_EMAIL);
    json(res, 200, { token }, req);
  } catch {
    json(res, 401, { error: "Unauthorized" }, req);
  }
}
async function handle(req, res) {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  const pathRaw = decodeURIComponent(url.pathname);

  if (req.method === "OPTIONS") {
    const h = corsForRequest(req);
    if (!h["Access-Control-Allow-Origin"]) {
      res.writeHead(403, { "Content-Length": "0" });
      return res.end();
    }
    res.writeHead(204, h);
    return res.end();
  }

  if (!pathRaw.startsWith(PREFIX)) {
    return json(res, 404, { error: "Not found" }, req);
  }

  const tail = pathRaw.slice(PREFIX.length).replace(/^\/+/, "");

  // GET + HEAD (curl -I / browsers preflight-ish probes send HEAD sometimes)
  if ((req.method === "GET" || req.method === "HEAD") && tail === "health") {
    const bodyObj = { ok: true, service: "whetstone-admin" };
    const body = JSON.stringify(bodyObj);
    const h = {
      "Content-Type": "application/json",
      ...corsForRequest(req),
    };
    if (req.method === "HEAD") {
      res.writeHead(200, { ...h, "Content-Length": Buffer.byteLength(body) });
      return res.end();
    }
    return json(res, 200, bodyObj, req);
  }

  if (req.method === "POST" && tail === "auth/supabase-exchange") {
    return await supabaseExchangeHandler(req, res);
  }

  if (req.method === "POST" && tail === "auth/login") {
    const body = await readJsonBody(req);
    if (body === undefined) return json(res, 400, { error: "Invalid JSON" }, req);
    return await loginHandler(body, req, res);
  }

  const auth = await verifyAdminToken(req.headers.authorization, req, res);
  if (auth === false) return;
  if (!auth) return json(res, 401, { error: "Unauthorized" }, req);

  if (!pool) return json(res, 500, { error: "DATABASE_URL missing" }, req);

  if (req.method === "GET" && tail === "stats") {
    return await statsHandler(req, res);
  }

  if (req.method === "GET" && tail === "storage") {
    return await storageHandler(req, res);
  }

  if (req.method === "GET" && tail === "conversations") {
    return await listConversations(url, req, res);
  }

  const convId = /^conversations\/([0-9a-fA-F-]{36})$/.exec(tail);
  if (convId) {
    const id = convId[1];
    if (req.method === "GET") return await getConversation(id, req, res);
    if (req.method === "PATCH") {
      const body = await readJsonBody(req);
      if (body === undefined) return json(res, 400, { error: "Invalid JSON" }, req);
      return await patchConversation(id, body, req, res);
    }
    if (req.method === "DELETE") return await deleteConversation(id, req, res);
  }

  if (req.method === "POST" && tail === "sql") {
    const body = await readJsonBody(req);
    if (body === undefined) return json(res, 400, { error: "Invalid JSON" }, req);
    return await sqlHandler(body, req, res);
  }

  return json(res, 404, { error: "Not found" }, req);
}

const server = http.createServer(async (req, res) => {
  try {
    await handle(req, res);
  } catch (e) {
    console.error(e);
    json(res, 500, { error: String(e?.message || e) }, req);
  }
});

server.listen(PORT, BIND, () => {
  console.log(`whetstone-admin listening on http://${BIND}:${PORT}${PREFIX}`);
});
