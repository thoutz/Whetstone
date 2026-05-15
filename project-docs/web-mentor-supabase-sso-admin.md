# Web mentor, marketing login, and owner SSO to Admin

Journal for the May 2026 work that adds a browser mentor at `https://projectwhetstone.net/app/`, Supabase sign-in on the marketing homepage, nginx exposure of the conversations API and Groq-compatible completions route, runtime `config.json` generation from VPS env, and a Supabase JWT exchange into the existing admin SPA session.

## Goals

- Same-origin browser flows that mirror iOS semantics: Bearer Supabase JWT to `/whetstone/api/*`, and `POST /v1/chat/completions` to the proxy with optional app token when configured.
- No public footer link to `/admin/`; owners reach Admin via gear after SSO exchange sets `sessionStorage.whetstone_admin_jwt`.

## Infrastructure

### Nginx

File: `server/deploy/nginx-projectwhetstone.conf`

- Proxies `/whetstone/api/` to the conversations API (`127.0.0.1:3001` by convention).
- Exposes `POST /v1/chat/completions` to the proxy (`127.0.0.1:8787`) with ample `client_max_body_size` for vision payloads.
- Serves SPA fallback for `/app/` to `app/index.html` where applicable.

Reload after deploy: `nginx -t && systemctl reload nginx` (exact command per server).

### Runtime config

- Deploy script runs `server/deploy/generate-web-app-config.py`, reading `/etc/whetstone-proxy.env` and writing `${REMOTE_WEB}/app/config.json`.
- Committed sample: `server/whetstone-website/app/config.sample.json` (placeholder values).
- **`config.json` fields**: `supabaseUrl`, `supabaseAnonKey`, `aiAppToken` (aliases `WHETSTONE_APP_TOKEN` / `AI_APP_TOKEN` from env), `aiModel`, `adminOwnerEmailLower` (from `ADMIN_EMAIL`, lowercased).

Ensure the VPS env file includes **at least**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ADMIN_EMAIL`, and optionally `WHETSTONE_APP_TOKEN` / `AI_MODEL`.

## Backend

### Shared Supabase verification

Module: `server/whetstone-shared/verify-supabase-access.mjs`

- Validates `Authorization: Bearer <access_token>` using JWKS (or JWT secret flow as configured), returns `{ sub, email }`.
- **Node resolution**: because this file lives under `/opt/whetstone-shared` on the server, **`jose`** and **`jsonwebtoken`** must be installed **`npm ci`** in **`server/whetstone-shared/`** (its own `package.json` + `package-lock.json`). Dependencies in **`whetstone-api/node_modules`** alone are **not** enough for imports from this path.

### Conversations API

File: `server/whetstone-api/index.mjs`

- Uses shared verifier for existing auth.
- **`GET /whetstone/api/me`** returns `{ sub, email }` for the SPA and landing owner check.

### Admin SSO bridge

File: `server/whetstone-admin/index.mjs`

- **`POST /admin/api/auth/supabase-exchange`** (no admin JWT): validates Supabase access token; if verified `email` (normalized, lowercased) equals `ADMIN_EMAIL`, responds with `{ token }` from `signAdminToken`, compatible with existing `admin/index.html` storage key `whetstone_admin_jwt`.

Dependency: `jsonwebtoken` (admin package) remains for admin-session signing.

## Frontend

### Marketing

File: `server/whetstone-website/index.html`

- Top-right **Log in** (**email + password** via Supabase, same shape as `/admin/` sign-in UX), **Open mentor** when signed in, **gear** menu (preferences stub, **Admin console** for owner only via `/whetstone/api/me` email vs `ADMIN_EMAIL`, **Log out**).
- Footer public Admin link removed.
- Utility class `.hidden` for showing/hiding nav controls.

### Mentor SPA

Path: `server/whetstone-website/app/index.html`

- Loads `/app/config.json` and `system_prompt.txt` (bundled copy of iOS persona).
- Conversations CRUD via `/whetstone/api/conversations` and PATCH with `api_history` / `ui_messages` shapes aligned with the iOS client.
- Chat loop against `/v1/chat/completions` with tools `render_construction` and `render_chips`; chips break the agentic loop until the user taps an option or sends a message.
- Multimodal: file input and paste → JPEG resize heuristic (~1024px); image-only turns use `(Student attached a photo with no caption.)` as API-visible text where applicable.

## Deploy

Script: `server/deploy/deploy-projectwhetstone-net.sh`

- Rsyncs website, **`--exclude node_modules`** for `whetstone-shared`, API, admin, nginx config, and copies `generate-web-app-config.py` to the server.
- Remote **`npm ci --omit=dev`** runs for **`REMOTE_SHARED`** first, then admin and API (shared deps must exist before restarting node services).
- Regenerates `${REMOTE_WEB}/app/config.json` from `/etc/whetstone-proxy.env`, reloads nginx, restarts **`whetstone-admin`**, **`whetstone-api`**, **`whetstone-proxy`**.

Password handling (`project-docs/server-login-info.txt`):

- Prefer **awk extraction** documented in that file (“line after Password header”), **not** a fixed sed line — the scripted helper lines would break `LOGIN_LINE=7`-style guesses.
- The deploy script prefers this file over a stray **`SSHPASS`** variable (IDE sandboxes often set **`SSHPASS`** incorrectly).

Post-deploy curls to **localhost** health URLs are advisory only (warnings if a unit is slow to bind); **`curl https://projectwhetstone.net/whetstone/api/health`** is the definitive public check.

## Verification checklist

1. `curl -sS https://projectwhetstone.net/whetstone/api/health`
2. After sign-in, `curl` `GET …/whetstone/api/me` with `Authorization: Bearer <access_token>`
3. From browser: sign in → `/app/` → send a text message and confirm assistant reply / tools if model supports them.
4. As owner (`ADMIN_EMAIL`): gear → Admin console → admin SPA loads without re-entering dashboard password.

## Follow-ups

- Tune markdown rendering in `/app/` to match Swift `MentorMarkdownView` over time if needed.
- Monitor proxy and nginx body limits under heavy multimodal threads.
