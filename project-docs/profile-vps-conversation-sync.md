# Profile sheet + VPS conversation sync

Journal for the Profile button, Postgres-backed REST API sync, iOS persistence client, and deploy wiring.

## Architecture

- **Auth:** Supabase (Apple Sign In) provides JWTs. The app sends `Authorization: Bearer <access_token>` to the VPS.
- **Chats:** Stored in **Postgres** on the VPS, scoped by JWT `sub` (user id). Same host origin as **`AI_BASE_URL`** from `Info.plist`; sync base path is **`/whetstone/api`** (derived in `WhetstoneConstants`).
- **Services on VPS:**
  - `whetstone-proxy` — Groq / OpenAI-compatible chat (existing).
  - `whetstone-api` — Node `server/whetstone-api/index.mjs`; listens on **`127.0.0.1:3001`** by default (**`WHETSTONE_API_PORT`**).
- **nginx:** `location ^~ /whetstone/api/` proxies to `3001`; `/` continues to Groq proxy on `8787`.

## iOS changes (paths)

| Area | Files |
|------|--------|
| Profile | `Auth/ProfileView.swift`, `Chat/ChatView.swift` — Profile replaces “I'm stuck”, sheet + sign-out, email / Apple private-email copy |
| Env | `WhetstoneConstants.swift` — `conversationsAPIBaseURL` / sync origin |
| REST | `AI/ConversationsAPIClient.swift` — Bearer from `SupabaseService`, list/detail/create/patch/delete |
| Codec / patch body | `Conversation/ConversationPersistence.swift` — wire DTOs, `ConversationHydration` |
| Store | `Conversation/ConversationStore.swift` — `remotePersistenceEnabled`, `applyAuthenticatedTransition`, `hydrateRemote`, `schedulePersist` after loop |
| Models | `Conversation.swift`, `ChatMessage.swift` — identifiers / mutability where needed |
| Target | `Whetstone.xcodeproj/project.pbxproj` — **`ProfileView.swift`**, **`ConversationPersistence.swift`**, **`ConversationsAPIClient.swift`** added to Sources |

Previews: `ChatView` preview includes **`AuthManager`** alongside **`ConversationStore`**.

## Server files

| Purpose | Path |
|---------|------|
| Schema | `server/deploy/schema-conversations.sql` |
| DB bootstrap | `server/deploy/postgres-whetstone.sh` |
| REST app | `server/whetstone-api/index.mjs`, `package.json` |
| systemd | `server/deploy/whetstone-api.service` |
| nginx | `server/deploy/nginx-whetstone.conf` — `location ^~ /whetstone/api/` → `proxy_pass http://127.0.0.1:3001/whetstone/api/` |
| One-shot installer | `server/deploy/install-on-server.sh` |

### `/etc/whetstone-proxy.env` (extended)

Groq-related keys unchanged. Add:

- **`DATABASE_URL`** — `postgres://whetstone:...@127.0.0.1:5432/whetstone_conv` (see `postgres-whetstone.sh` output).
- **`SUPABASE_JWT_SECRET`** — Dashboard → Settings → API → JWT Secret (same project as the app’s anon URL/key).
- Optional: **`WHETSTONE_API_PORT`**, **`WHETSTONE_API_BIND`**.

## VPS install steps

1. Upload `server/` to the VPS (see `project-docs/server-deployment.md`).
2. Run installer:

   ```bash
   sudo bash deploy/install-on-server.sh
   ```

   Optional **Postgres + schema** in one go:

   ```bash
   WHETSTONE_SETUP_POSTGRES=1 WHETSTONE_PG_PASSWORD='choose-a-strong-password' sudo -E bash deploy/install-on-server.sh
   ```

3. Edit **`/etc/whetstone-proxy.env`**: **`GROQ_API_KEY`**, **`DATABASE_URL`**, **`SUPABASE_JWT_SECRET`** (if Postgres was not scripted, run `postgres-whetstone.sh` and paste **`DATABASE_URL`**).
4. Restart:

   ```bash
   systemctl restart whetstone-proxy whetstone-api
   systemctl reload nginx
   ```

5. Sanity checks:

   ```bash
   curl -fsS http://127.0.0.1:3001/whetstone/api/health
   ```

## Troubleshooting fixes (this sprint)

1. **`ConversationPersistence`:** `PersistedSvgDTO` / `PersistedMetaDTO` could not remain `private` while referenced by public `WireUIMessageExtrasDTO` — structs are internal.
2. **`ConversationStore`:** `schedulePersist(conversationId:)` requires the **`conversationId:`** label at call sites.
3. **`ProfileView.loadEmail()`:** Loads via `try await client.auth.session`; **`MainActor.run`** for `@State`; placeholder when Apple hides email.
4. **Conversation API 404 on hydrate:** `whetstone-api` matched list paths but detail paths had a `/`/`conversations/` regex mismatch; fixed with **`tail`** normalization (+ optional stripped-prefix). nginx uses explicit **`proxy_pass …/whetstone/api/`**. Supabase linkage is JWT **`sub`** → **`user_id`** + matching **`SUPABASE_JWT_SECRET`** — see **`project-docs/conversation-api-404-supabase-account-link.md`**.

## Xcode verification

From repo root:

```bash
xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build
```
