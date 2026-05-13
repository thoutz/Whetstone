# Auth chain — expired token + identity stability

Journal for implementing the plan “Fix: Auth Chain — Expired Token + Identity Stability”.

## Problem

`ConversationsAPIClient.bearerToken()` originally returned `session.accessToken` without ensuring validity. Expired tokens and **parallel `hydrateRemote` tasks each calling `refreshSession()`** led to intermittent `401 {"error":"Unauthorized"}` from [`server/whetstone-api/index.mjs`](../server/whetstone-api/index.mjs). Supabase-swift also warns that **`emitLocalSessionAsInitialSession: true`** must be paired with **`session.isExpired`** before trusting tokens (PR #822).

Hide My Email does **not** affect linkage: VPS rows use JWT claim `sub` (`auth.users.id`), not email.

## iOS changes

| File | Change |
|------|--------|
| [`Whetstone/AI/ConversationsAPIClient.swift`](../Whetstone/AI/ConversationsAPIClient.swift) | `bearerToken()` uses `session.isExpired` (SDK margin ~30s); refreshes via `refreshSession()` when needed. Overloads `fetchConversationSummaries(authorizationHeader:)` and `fetchConversationDetail(..., authorizationHeader:)` so hydrate reuses one header after a single refresh (no concurrent refresh races). |
| [`Whetstone/Auth/AuthManager.swift`](../Whetstone/Auth/AuthManager.swift) | `restoreSession()` uses `(try? await client.auth.session) != nil` — token freshness lives in `bearerToken()` / API calls. |
| [`Whetstone/Auth/SupabaseService.swift`](../Whetstone/Auth/SupabaseService.swift) | **`emitLocalSessionAsInitialSession: true`** per supabase-swift PR #822 / runtime warning — pair with `session.isExpired` in `bearerToken()`. |
| [`Whetstone/Conversation/ConversationStore.swift`](../Whetstone/Conversation/ConversationStore.swift) | `hydrateRemote()` calls `authorizationHeaderValue()` once, then passes that header into list + all parallel detail fetches. |

## Server changes

| Location | Change |
|----------|--------|
| Repo [`server/whetstone-api/index.mjs`](../server/whetstone-api/index.mjs) | `jwt.verify(..., { algorithms: ["HS256"], clockTolerance: 30 })` |
| VPS `/opt/whetstone-api/index.mjs` | Deployed via `scp` from repo; `systemctl restart whetstone-api`; health check OK. |

## Verification

- **Build:** `xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build` → succeeded.
- **VPS health:** `curl http://127.0.0.1:3001/whetstone/api/health` → `{"ok":true,"service":"whetstone-api"}`.
- **Postgres diagnostic:** `SELECT user_id, count(*), max(updated_at) FROM conversations GROUP BY user_id` → **0 rows** (no synced conversations yet; expected while 401 blocked writes).

## Follow-up

After the next successful sync, re-run the SQL above: multiple `user_id` values would indicate different Supabase users (e.g. bundle/team change), not email privacy.
