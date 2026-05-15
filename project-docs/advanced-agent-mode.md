# Advanced Agent Mode

Implementation journal for the **Standard vs Advanced** agent modes (May 2026).

## Goals

- **Standard** — unchanged product behavior: mentor system prompt from `system_prompt.txt`, tools `render_construction` + `render_chips` only.
- **Advanced** — Supabase-gated power users: alternate system prompt (`advanced_system_prompt.txt`), mentor tools plus eight on-device network/SSH tools, no generative discipline from the mentor prompt while keeping safety wording.
- **Enforcement** — Server-side entitlement in JWT (`app_metadata.advanced_mode`). UI toggle without entitlement does nothing effective; runtime uses Standard tools/prompt whenever `AuthManager.isAdvancedUser` is false.

## Supabase setup (admin)

1. Dashboard → Authentication → Users → choose user → **Edit user metadata**.
2. Under **Custom app metadata** (or raw JSON depending on UI), add:
   ```json
   { "advanced_mode": true }
   ```
3. Force a fresh session so the **access JWT** picks up the flag (sign out/in, or refresh if your client auto-refreshes).

The app decodes the **access token** payload (middle JWT segment) and reads `app_metadata.advanced_mode` as bool / int / string (`1`, `true`, etc.).

## Xcode / SwiftPM

- Added remote package **Citadel** (`https://github.com/orlandos-nl/Citadel.git`, resolved to **0.12.1** at time of implementation) for SSH.
- Product linked to target: **Citadel**.
- Resolved graph also pulls **swift-nio**, **swift-nio-ssh**, **BigInt**, **swift-log**, etc. (see `Package.resolved` after resolve).

Files added to the target:

| File | Role |
|------|------|
| `Whetstone/AgentMode.swift` | `AgentMode` enum, bundled prompt loader, `AgentModeStore` (UserDefaults `whetstone.agentMode`). |
| `Whetstone/Auth/SupabaseJWTHelper.swift` | Base64-url JWT payload decode → `advanced_mode`. |
| `Whetstone/AI/AdvancedTools.swift` | Tool schemas + implementations. |
| `Whetstone/Resources/advanced_system_prompt.txt` | Advanced system instructions (bundled resource). |

## Runtime wiring

- `WhetstoneApp` constructs one `AuthManager`, one `AgentModeStore`, one `ConversationStore(agentModeStore:auth:)` via `StateObject` initializers (single shared auth instance).
- `.environmentObject(agentModeStore)` on the root so `ChatView` / `ProfileView` can observe mode.
- `.task(id: auth.isAuthenticated)` — existing sync path; also calls `auth.refreshEntitlementFromSession()` after login so JWT flags apply without extra taps.
- `.task(id: auth.isAdvancedUser)` — `AgentModeStore.revertToStandardIfNotEntitled` when entitlement is revoked.

## Conversation / hydration

- `ConversationStore.effectiveAgentModeForChat` requires both `AgentModeStore.mode == .advanced` **and** `auth.isAdvancedUser`.
- Each `runLoop` snapshot selects:
  - system prompt via `AgentMode.bundledPrompt(for:)`
  - tool list: `MentorTools.all` vs `MentorTools.all + AdvancedTools.all`
- `ConversationHydration.decodeConversation` takes `systemPromptVariants: [String]` (`AgentMode.allBundledPromptStrings`) so duplicate legacy `.system` rows strip correctly for either prompt variant.

## Tool dispatch

- `dispatchToolCall(_:advancedToolsEnabled:)` in `MentorTools.swift` is **async**; mentor handlers stay synchronous; advanced path `await`s `AdvancedTools.dispatch`.
- `AdvancedTools`: `dns_lookup`, `ping_host` (TCP, not ICMP), `ip_geolocation` (ipinfo.io), `port_scan`, `http_request`, `whois_lookup` (rdap.org), `network_interfaces`, `ssh_execute` (Citadel, password auth, `SSHHostKeyValidator.acceptAnything()` — documented risk in tool description).

## UI

- **Profile** — Section “Agent mode” with Standard/Advanced capsule, toggle (disabled with copy when `!isAdvancedUser`), subtitle for locked vs unlocked.
- **Chat HUD** — Trailing badge `ADVANCED` when effective advanced (preference + entitlement).
- **Preview harnesses** — `ChatPreviewContainer` wires shared auth + mode + store; `ProfileView` preview includes `AgentModeStore`.

## Local network note

Outbound TCP probes / scans may interact with LAN targets. If iOS prompts for local network permission in your environment, add `NSLocalNetworkUsageDescription` in the target Info (not added automatically in this pass — add when you observe the permission sheet).

## Follow-ups (optional)

- Token refresh observer to re-run `refreshEntitlementFromSession()` whenever Supabase rotates JWT.
- Structured logging redaction for tool payloads containing passwords (currently only model + tool messages in history).
- Key-based SSH (Citadel supports ed25519/RSA) if password auth is insufficient.
