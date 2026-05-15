# Whetstone website + admin dashboard (projectwhetstone.net)

Journal for the **marketing site** and **admin-only dashboard** that manage the VPS Postgres database used by `whetstone-api` (conversation sync).

## Goal

- Public **landing page** at **https://projectwhetstone.net/** — dark/minimal positioning for the Whetstone iOS mentor (no substantive style changes tied to existing app UI; this is a separate static web surface).
- **Admin** (`/admin/`) — email + password login, JWT session (`sessionStorage`), then:
  - **Overview** — counts (users, conversations, messages, summed tokens), 7‑day messages bar chart (Canvas), plus **database + host storage meters** (`pg_database_size`, top relation sizes via `GET /admin/api/storage`, optional `df -k` on **`ADMIN_DF_PATH`** — default **`/`**).
  - **Conversations** — global list, **advanced filters** (title, message body substring, UUID partial/exact, updated range, token min/max, sort), optional **linked Supabase Auth display name + email** on each row/detail when **`SUPABASE_SERVICE_ROLE_KEY`** is set; open thread, PATCH title, DELETE.
  - **SQL console** — arbitrary Postgres read/write capped to 5000 returned rows.

## Repo layout

| Path | Purpose |
|------|---------|
| [server/whetstone-website/index.html](server/whetstone-website/index.html) | Public landing (`index.html` only; inlined CSS — Google Fonts Instrument Serif + Source Sans 3) |
| [server/whetstone-website/admin/index.html](server/whetstone-website/admin/index.html) | Admin SPA (single file; inlined CSS + vanilla JS) |
| [server/whetstone-admin/index.mjs](server/whetstone-admin/index.mjs) | Admin Node HTTP API (`PREFIX=/admin/api`) |
| [server/whetstone-admin/package.json](server/whetstone-admin/package.json) | `pg`, `jose` |
| [server/deploy/nginx-projectwhetstone.conf](server/deploy/nginx-projectwhetstone.conf) | Nginx server block for the new domain |
| [server/deploy/whetstone-admin.service](server/deploy/whetstone-admin.service) | systemd unit |
| [server/deploy/nginx-whetstone.conf](server/deploy/nginx-whetstone.conf) | sslip/iOS-only vhost (`149-28-38-55.sslip.io`) — clarified as separate from the marketing domain |

There is **no separate CSS bundle** beyond what is inlined in the two HTML files (per plan: standalone static deployment).

### “Installation” locally (sanity check)

```bash
cd server/whetstone-admin
npm install
export DATABASE_URL='postgres://…'
export ADMIN_EMAIL='thoutz@gmail.com'
export ADMIN_PASSWORD='your-long-password'
export ADMIN_JWT_SECRET='random-32+bytes-secret'
export SUPABASE_URL='https://<project-ref>.supabase.co'
# Optional — enables conversation list/detail user_display_name + user_email via GoTrue admin API:
# export SUPABASE_SERVICE_ROLE_KEY='<service_role_secret>'
ADMIN_CORS_ORIGINS='http://localhost:5173,https://projectwhetstone.net' WHETSTONE_ADMIN_PORT=3002 node index.mjs
```

Point a throwaway reverse proxy from `/admin/` + `/admin/api/` to files + port 3002, or curl `http://127.0.0.1:3002/admin/api/health`.

## VPS placement

Assumed filesystem on the VPS (matches nginx snippet):

```
/var/www/whetstone-website/index.html
/var/www/whetstone-website/admin/index.html
```

Node service binaries (matching existing `whetstone-api.service` convention):

```
/opt/whetstone-admin/index.mjs
/opt/whetstone-admin/node_modules/…
/opt/whetstone-admin/package.json
```

### Environment (`/etc/whetstone-proxy.env`)

Reuse existing `DATABASE_URL` if already present.

Add:

```bash
ADMIN_EMAIL=thoutz@gmail.com
ADMIN_PASSWORD=<long random passphrase>
ADMIN_JWT_SECRET=<long random secret for HS256>
# Optional comma-separated HTTPS origins allowed to hit the browser API:
# ADMIN_CORS_ORIGINS=https://projectwhetstone.net,https://www.projectwhetstone.net
# Optional mount path passed to POSIX `df -k` for a host-disk use bar on the admin Overview (often "/"; may point at Postgres data disk if separated):
# ADMIN_DF_PATH=/
#
# Already present for other Whetstone services:
# SUPABASE_URL=https://<project-ref>.supabase.co
# Optional admin-only — resolves display name/email from hosted Auth (never ship to the mobile app):
# SUPABASE_SERVICE_ROLE_KEY=<paste service_role from Supabase dashboard>
```

The admin service reads the same env file (`EnvironmentFile=` in systemd).

Display names map from Apple / Supabase registration metadata (`full_name`, `name`, identities’ `identity_data`, etc.).

Ports:

| Service | Bind | Prefix |
|---------|------|--------|
| `whetstone-admin` | `127.0.0.1:3002` | `/admin/api` |

## Nginx / TLS / DNS

1. Copy repo `server/deploy/nginx-projectwhetstone.conf` to `/etc/nginx/sites-available/projectwhetstone` (or equivalent) and enable the site symlink.
2. `sudo nginx -t && sudo systemctl reload nginx`.
3. **DNS**: `projectwhetstone.net` (and `www` if used) → **A** record **149.28.38.55** (IPv6 AAAA optional).
4. **Certbot** (once HTTP answers on that hostname):

```bash
sudo certbot --nginx -d projectwhetstone.net -d www.projectwhetstone.net
```

The **iOS Groq proxy** continues to terminate on **`149-28-38-55.sslip.io`** via `nginx-whetstone.conf`; **`projectwhetstone.net`** is a **separate** `server { … }`.

## systemd

```bash
sudo rsync -a server/whetstone-admin/ /opt/whetstone-admin/
cd /opt/whetstone-admin && sudo npm ci --omit=dev
sudo cp /path/to/repo/server/deploy/whetstone-admin.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now whetstone-admin
```

Health check:

```bash
curl -sS http://127.0.0.1:3002/admin/api/health
```

## Admin API cheat sheet (`Authorization: Bearer <jwt>` unless noted)

| Method | Path | Body | Notes |
|--------|------|------|-------|
| `POST` | `/admin/api/auth/login` | `{ email, password }` | Returns `{ token }` |
| `GET` | `/admin/api/stats` | — | Aggregate counts + `messages_by_day` |
| `GET` | `/admin/api/storage` | — | Postgres `database` (`pg_database_size` + pretty), top 24 relations (`tables`), `table_sum_bytes`, optional `host_volume` from **`df -k $ADMIN_DF_PATH`**, `df_path`, `note` |
| `GET` | `/admin/api/conversations` | — | Query: `page`, `limit`, `q` (title ILIKE), `message_contains`, `user_id_part`, `user_id` (full UUID), `updated_after`, `updated_before` (ISO), `min_tokens`, `max_tokens`, `sort` (`updated_desc`/`updated_asc`/`created_*`/`tokens_*`). Response includes `user_display_name`, `user_email` when **`SUPABASE_SERVICE_ROLE_KEY`** is set (`user_profiles_enabled` boolean). |
| `GET` | `/admin/api/conversations/:id` | — | Includes `messages` + same user fields |
| `PATCH` | `/admin/api/conversations/:id` | `{ title }` | Updates title |
| `DELETE` | `/admin/api/conversations/:id` | — | Hard delete (+ cascade messages) |
| `POST` | `/admin/api/sql` | `{ sql }` | **Dangerous**. Returns table first 5000 rows for SELECT-ish results; otherwise `{ note, rowCount }` |

### Security notes

- SQL console accepts **arbitrary SQL** (including `DELETE` and DDL); protect secrets and expose only behind HTTPS + strong password/JWT secret.
- CORS reflects **allowed origins only** (`ADMIN_CORS_ORIGINS` fallback: apex + www).
- Login password is verified with a constant-time-ish buffer compare (`timingSafeEq`).
- **Service role is root on Supabase.** Keep **`SUPABASE_SERVICE_ROLE_KEY`** only on the VPS; never bake it into the iOS binary.

## Frontend behavior notes

- API base **`/admin/api`** (same origin when served from nginx root).
- Wrong-password **401 on login does not wipe** an unrelated token (SPA checks `path !== '/auth/login'` before forced logout).

## Troubleshooting

| Symptom | Likely fix |
|---------|-------------|
| `curl -I`/HEAD to `/admin/api/health` returns 401 via nginx while GET works | **Fixed in code**: health allows `HEAD` as well as `GET` (monitors sometimes use HEAD). Upgrade `index.mjs` on the VPS and `systemctl restart whetstone-admin`. |
| CORS failures in browser | Add your exact `https://` origin(s) via `ADMIN_CORS_ORIGINS` |
| nginx 502 on `/admin/api/` | `systemctl status whetstone-admin`, confirm port 3002 |
| Admin login **`Failed to fetch`** / TLS error — site was briefly **HTTP-only** | The active `projectwhetstone` vhost **must listen on `:443`** with certs under **`/etc/letsencrypt/live/projectwhetstone.net/`** (see **`server/deploy/nginx-projectwhetstone.conf`**). Replacing nginx with HTTP-only pushes HTTPS clients onto the sslip TLS vhost and breaks the hostname. Reload nginx after restoring the `:443` block. |
| 500 “ADMIN_JWT_SECRET missing” | Set secret + restart systemd |
| Site shows default nginx page | Wrong `root` or files not deployed under `/var/www/whetstone-website` |
| Account column only shows UUID | Set **`SUPABASE_URL`** + **`SUPABASE_SERVICE_ROLE_KEY`** then `systemctl restart whetstone-admin` |

## VPS deploy log (automated SSH)

Deployed from this repo to **`149.28.38.55`**: `/var/www/whetstone-website/`, **`/opt/whetstone-admin/`**, nginx site **`/etc/nginx/sites-available/projectwhetstone`**, and **`whetstone-admin.service`** (enabled).

Quick deploy (from repo root). The script uses **`sshpass`** + the root password on **line 7** of **`project-docs/server-login-info.txt`** (override with **`SSHPASS`** or **`LOGIN_LINE`** — never commit secrets):

```bash
./server/deploy/deploy-projectwhetstone-net.sh
```

If **`sshpass`** is missing: **`brew install sshpass`**. Without password material, the script falls back to **public-key** **`BatchMode`** ssh (add your **`~/.ssh/id_ed25519.pub`** to the server’s **`authorized_keys`** if you prefer keys).

### Cursor / agent note

Automated deploy uses **`sshpass`** and the password file above (same approach as the original site rollout). Public-key-only **`ssh`** from the agent fails with **Permission denied** until a key is authorized or **`sshpass`** + **`server-login-info.txt`** are present.

**Admin env:** If **`ADMIN_EMAIL=`** was absent, **`ADMIN_EMAIL`**, **`ADMIN_PASSWORD`**, and **`ADMIN_JWT_SECRET`** were appended to **`/etc/whetstone-proxy.env`**. Retrieve on the VPS as **`root`** (do not paste into shared channels):

```bash
grep '^ADMIN_' /etc/whetstone-proxy.env
```

**TLS:** Completed on the VPS with Let's Encrypt (certbot **`--nginx`** for **`projectwhetstone.net`** and **`www`**). HTTP now redirects to HTTPS. Certificate path: **`/etc/letsencrypt/live/projectwhetstone.net/`** (auto-renew scheduled by certbot).

## Related docs

- [server-deployment.md](server-deployment.md) — TLS + proxy rollout for sslip hostname
- [schema-conversations.sql](../server/deploy/schema-conversations.sql) — Postgres schema the dashboard operates on
