# Sign in with Apple — Supabase Auth

## Overview

Added a full-screen login gate to Whetstone using Sign in with Apple, backed by the same Supabase project as FrameIOS. No users table required — session auth alone gates access to the mentor chat.

## Files Created / Modified

### New files
| File | Purpose |
|---|---|
| `Whetstone/WhetstoneConstants.swift` | Reads `SupabaseURL` and `SupabaseAnonKey` from Info.plist (with DEBUG env-var fallback). Same pattern as FrameIOS `FrameConstants`. |
| `Whetstone/Auth/SupabaseService.swift` | Singleton `SupabaseClient` (anon key only, never service role). Nil-safe: returns `nil` when keys are missing. |
| `Whetstone/Auth/AuthManager.swift` | `@MainActor ObservableObject`. Handles: session restore on launch, SHA-256 nonce generation for Apple, `handleAppleSignIn`, `signOut`. |
| `Whetstone/Auth/LoginView.swift` | Full-screen login UI matching WhetstoneTheme. Diamond blade-mark icon, tracked "WHETSTONE" wordmark, `SignInWithAppleButton` (white style). Shows amber callout when Supabase keys are missing. |

### Modified files
| File | Change |
|---|---|
| `Whetstone/Info.plist` | Added `SupabaseURL` and `SupabaseAnonKey` keys (empty — fill in from Supabase dashboard). |
| `Whetstone/WhetstoneApp.swift` | `AuthManager` injected as `@StateObject`. Shows `LoginView` when not authenticated, `DrawerContainer → ChatView` when authenticated. Both branches inject `auth` as an environment object. |

## Apple Developer Portal (already done prior to this implementation)

- App ID `com.thoutz.whetstone` registered with **Sign in with Apple** capability enabled.
- Existing team-level Sign in with Apple key reused (team-scoped — covers all App IDs).
- Whetstone bundle ID added to Supabase Dashboard → Authentication → Providers → Apple → Client IDs.
- No Services ID required (native iOS flow, not web OAuth).

## Xcode Steps Required

1. **Add `supabase-swift` package:**
   File → Add Package Dependencies → `https://github.com/supabase/supabase-swift` → add `Supabase` library to Whetstone target.

2. **Enable Sign in with Apple capability:**
   Target → Signing & Capabilities → `+` → Sign in with Apple.

3. **Fill in Info.plist keys:**
   Open `Whetstone/Info.plist` in Xcode → set `SupabaseURL` and `SupabaseAnonKey` from the Supabase dashboard (Settings → API).
   - URL: `https://<ref>.supabase.co`
   - Anon key: the `anon` / `public` key (never the service role key)

4. **Add new Auth folder to Xcode project navigator:**
   Drag `Whetstone/Auth/` into the navigator with "Copy items if needed" **off**, target membership checked.

## Auth Flow

```
App launch
  └─ AuthManager.init()
       └─ restoreSession() → checks for existing Supabase session
            ├─ session exists → isAuthenticated = true → ChatView shown
            └─ no session    → isAuthenticated = false → LoginView shown

User taps Sign in with Apple
  └─ prepareAppleNonce() → stores raw nonce, returns SHA-256 for Apple
  └─ Apple returns ASAuthorizationAppleIDCredential
  └─ handleAppleSignIn()
       └─ client.auth.signInWithIdToken(provider: .apple, idToken:, nonce:)
            ├─ success → isAuthenticated = true → view switches to ChatView
            └─ failure → errorMessage shown in LoginView
```

## Design Choices vs FrameIOS

| FrameIOS | Whetstone |
|---|---|
| Queries `public.users` table for profile | No users table — session token is sufficient |
| Invite code gate + join request flow | None (open access) |
| Profile setup screen | None in Phase 1 |
| Philosophy acceptance screen | None |
| `AuthServiceProtocol` abstraction | Direct Supabase calls in `AuthManager` (simpler) |

The simplified approach is intentional. Whetstone's auth purpose is identity continuity for conversation history sync (future Supabase backlog item) — not gating a social platform.

## Security Notes

- Anon key only in the bundle. Service role key lives only on the VPS (`/etc/whetstone-proxy.env`).
- `SupabaseAnonKey` and `SupabaseURL` should ideally move to an xcconfig (gitignored) before App Store submission — the pattern in `WhetstoneConstants.swift` supports this already (reads plist key which xcconfig can substitute via `$(SUPABASE_ANON_KEY)` build setting).
- `user_metadata` (including Apple full name) is never used for authorization decisions.
