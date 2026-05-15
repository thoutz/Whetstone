# Admin dashboard: Postgres + host storage meters

Journal for adding **Overview** storage monitoring (database logical size, per-table totals, optional host-disk bar).

## What changed

### Backend (`server/whetstone-admin/index.mjs`)

- Added **`ADMIN_DF_PATH`** (default **`/`**): path argument to **`df -k`** for best-effort **host volume used %** alongside Postgres metrics (non-fatal if `df` fails).
- Implemented **`storageHandler`** and routed **`GET /admin/api/storage`** (JWT‑protected).
- Queries:
  - **`pg_database_size(current_database())`** for the connected DB.
  - Top **24** user tables (non-system schemas) by **`pg_total_relation_size`**, with table vs index byte columns for future use.
- **`dfHostHint`**: parses standard two-line `df -k` output; sets **`use_percent`** from the capacity column when parseable.

### Frontend (`server/whetstone-website/admin/index.html`)

- New panel **“Database & server storage”** under Overview.
- **`refreshOverview`** uses **`Promise.allSettled`** for **`/stats`** and **`/storage`** so a storage failure still shows counts/chart; top banner reports partial failure.
- CSS: **`.meter-track` / `.meter-fill`** (with warn/danger classes for high disk use), table row grid for largest relations.

### Docs

- Updated **[website-admin-dashboard.md](website-admin-dashboard.md)** (Overview description, env var comment, API table row for **`/storage`**).

## Deploy

1. Rsync **`index.mjs`** to **`/opt/whetstone-admin/`** and **`admin/index.html`** to **`/var/www/whetstone-website/admin/`** (or your paths).
2. Optionally set **`ADMIN_DF_PATH`** in **`/etc/whetstone-proxy.env`** to a mount that reflects the volume you care about (often **`/`**; use the Postgres data mount if it differs).
3. **`systemctl restart whetstone-admin`**.

## If you still see the old Overview (no “Database & server storage”)

1. **Confirm the VPS is serving fresh HTML**

   ```bash
   curl -sS 'https://projectwhetstone.net/admin/index.html' | grep -F 'storageWrap' && echo 'OK: new bundle on server'
   ```

   No match → **`admin/index.html` was not copied** to **`/var/www/whetstone-website/admin/`** (or nginx `root` points elsewhere).

2. **Hard refresh** the tab (cache): **Safari**: empty cache option or **⌘⌥R** / **⇧⌘R** depending on OS; **Chrome**: **⇧⌘R**.

3. **Restart the Node process** after updating **`index.mjs`** (`GET /storage` exists only on the new build):

   ```bash
   sudo systemctl restart whetstone-admin
   ```

Repo nginx snippet now sends **`Cache-Control: no-store`** for **`/admin/`** ([`nginx-projectwhetstone.conf`](../server/deploy/nginx-projectwhetstone.conf)) — copy onto the VPS and **`nginx -t && systemctl reload nginx`** so updates are not swallowed by stale HTML caches.

On the VPS, **`certbot`** may have duplicated **`server { … }`** blocks — add the same **`add_header`** (or **`include`** a snippet) inside the **`location ^~ /admin/`** block that serves HTTPS.

## Smoke test

```bash
# After login, token in hand:
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:3002/admin/api/storage | jq .
```

Expected keys: **`database`**, **`tables`**, **`table_sum_bytes`**, optional **`host_volume`**, **`df_path`**, **`note`**, **`collected_at`**.
