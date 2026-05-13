# Conversation API 401 — Stale Access Token Fix

## Symptom

After sign-in (or app relaunch), the alert appeared:

> Configuration — Could not load your conversations: Conversation API (401): {"error":"Unauthorized"}

## Diagnosis (verified steps)

| Check | Result |
|---|---|
| `curl https://149-28-38-55.sslip.io/whetstone/api/health` | `{"ok":true,"service":"whetstone-api"}` ✅ |
| nginx routes `/whetstone/api/` to port 3001 | Confirmed — not the cause |
| `whetstone-api` service status | `active` ✅ |
| `SUPABASE_JWT_SECRET` in `/etc/whetstone-proxy.env` | Set and **correct** — verified by successfully signing the Supabase anon key JWT with it |
| Server clock (NTP) | Synchronized ✅ |
| Test request with freshly-signed JWT | Returned `{"conversations":[]}` — server 100% correct |

**Root cause:** The 401 was iOS-side. `AuthManager.restoreSession()` only called `client.auth.session` to check if a session exists, but never explicitly refreshed the access token. With `emitLocalSessionAsInitialSession: true` in `SupabaseClientOptions`, the Supabase-swift SDK can surface a locally-cached (expired) access token before its background refresh completes. `hydrateRemote()` then immediately calls `bearerToken()` and sends that stale token to the server, which correctly rejects it with 401.

## Fix

### `Auth/AuthManager.swift` — `restoreSession()`

Changed from a one-liner existence check to:
1. Confirm session exists
2. Explicitly call `client.auth.refreshSession()` (best-effort — if offline, `try?` keeps the existing session)
3. Set `isAuthenticated = true` only after the above

This guarantees the access token is fresh before `hydrateRemote()` runs.

### `Conversation/ConversationStore.swift` — `hydrateRemote()`

No change from original behavior: a sync failure (including 401) shows the error banner and starts a fresh local conversation. Signing the user out on a sync 401 was tried but reverted — it caused a login loop when the refresh token was expired, evicting users who still had a valid app experience available.

### `WhetstoneApp.swift`

No change — `applyAuthenticatedTransition(isAuthenticated:)` signature is unchanged.

## VPS — no changes required

The server was already correctly configured. `SUPABASE_JWT_SECRET` was set and valid. The `whetstone-api` service, nginx routing, and Postgres connection were all healthy.
