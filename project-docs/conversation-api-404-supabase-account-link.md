# Conversation API 404 and Supabase account ↔ VPS Postgres

## Symptoms

- iOS Configuration alert: `Conversation API (404): {"error":"Not found"}` after sign-in.

## Cause (fixed in repo)

1. **Broken path matching in [`server/whetstone-api/index.mjs`](../server/whetstone-api/index.mjs):** After removing the `/whetstone/api` prefix, `rest` was `/conversations/<uuid>` (leading slash). Handlers matched `^conversations/…`, so **`GET …/conversations/<id>`** always 404’d while **`GET …/conversations`** (list) could still succeed. Hydration loads the list then fetches each detail — detail failed → user-facing error.

2. **nginx:** Repo template now uses `proxy_pass http://127.0.0.1:3001/whetstone/api/;` inside `location ^~ /whetstone/api/` so upstream always receives `/whetstone/api/…`. If HTTPS server blocks omit this `location` after certbot, traffic can hit the Groq proxy (8787) and return the same JSON 404 shape.

## How accounts “link” (no separate link table)

There is **no** extra linkage step besides:

1. **`SUPABASE_JWT_SECRET`** in `/etc/whetstone-proxy.env` must equal **Supabase Dashboard → Settings → API → JWT Secret** for the **same project** as the app’s **`SupabaseURL`** / **`SupabaseAnonKey`**.
2. On each request the API verifies the Bearer token, reads **`sub`**, and uses it as Postgres **`user_id`** (UUID = `auth.users.id`).

`conversations.user_id` rows are keyed by that UUID; **`ON CONFLICT` / INSERT** use the authenticated `sub` only.

## VPS applied (manual SSH)

PostgreSQL (**`whetstone_conv`**), **`whetstone-api`** on **`127.0.0.1:3001`**, and the **HTTPS** nginx `location ^~ /whetstone/api/` block were deployed to **`149.28.38.55`**. **`https://149-28-38-55.sslip.io/whetstone/api/health`** returns **`{"ok":true,"service":"whetstone-api"}`**.

**Still required:** set **`SUPABASE_JWT_SECRET`** in **`/etc/whetstone-proxy.env`** (JWT Secret from Supabase Dashboard for project **`eqymsphqkskaleprmlds`**, matching **`Info.plist`**), then:

`systemctl restart whetstone-api`

Without that value, authenticated conversation routes respond with **`500`** (`SUPABASE_JWT_SECRET missing`).

