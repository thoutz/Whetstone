# Profile credential vault (saved passwords + SSH identities)

**Date:** 2026-05-15  

## Summary

Device-local credential storage for Advanced Mode: metadata in `UserDefaults` (`whetstone.vault.index` JSON), secrets only in **Keychain** (service `com.thoutz.whetstone.vault`, accounts `password.<uuid>` and `sshPrivateKey.<uuid>`), accessibility `after first unlock`, **this device only**, not synchronizable. Profile shows **Saved passwords** and **SSH identities** only when `auth.isAdvancedUser && agentModeStore.mode == .advanced`.

Each entry includes **`allowAgentUse`** (default off). Tools resolve `saved_password_id` / `saved_ssh_identity_id` only when that flag is on; Profile clipboard copy ignores the flag (`passwordSecretForClipboard`).

## Files

| Piece | Location |
|--------|----------|
| Keychain + index + protocol + store | `Whetstone/Auth/CredentialVault.swift` |
| Profile UI | `Whetstone/Auth/ProfileView.swift` (ScrollView + sheets + pasteboard TTL) |
| Tool dispatch + SSH | `Whetstone/AI/AdvancedTools.swift` (`ssh_execute` mutual exclusivity; Citadel Ed25519/RSA PEM via `Curve25519.Signing.PrivateKey(sshEd25519:)` / `Insecure.RSA.PrivateKey(sshRsa:)`; optional `key_passphrase`) |
| Injection into loop | `Whetstone/AI/MentorTools.swift` — `dispatchToolCall(..., credentialVault:)` |
| Wired from chat | `Whetstone/Conversation/ConversationStore.swift` — passes `credentialVaultStore` only when Advanced mode snapshot is active |
| App lifecycle | `Whetstone/WhetstoneApp.swift`, `Whetstone/Chat/ChatView.swift` — `environmentObject(CredentialVaultStore)` |
| Prompt | `Whetstone/Resources/advanced_system_prompt.txt` |
| Xcode | `Whetstone.xcodeproj/project.pbxproj` — `CredentialVault.swift` |

## SSH tool contract (`ssh_execute`)

- **Required:** `host`, `command`.
- Provide **exactly one** auth path: inline `password`, or `saved_password_id`, or `saved_ssh_identity_id` (UUID string).
- **`username`:** required except when omitted and the SSH vault entry defines a **default username** (`saved_ssh_identity_id` branch).
- **`key_passphrase`:** decrypts bcrypt-protected OpenSSH PEM when applicable.
- **Supported vault keys:** OpenSSH PEM; types **Ed25519** or **RSA** (ECDSA not wired).
- Resolved secrets stay off the transcript; tool errors surface as `LocalizedError` text.

## Tester checklist

1. Standard mode or non-entitled: Profile has **no** vault sections.
2. Advanced + entitled, vault UI visible: add password with `allowAgentUse` **off** → `ssh_execute` with that `saved_password_id` returns permission-style tool error.
3. Same entry, **on** → password SSH connects (against a lab host).
4. SSH identity PEM (Ed25519 or RSA), `allowAgentUse` **on** → key auth path works; encrypted PEM needs `key_passphrase`.
5. Delete entry → Keychain item removed (and row gone after restart still gone).
6. Copy password → pasteboard TTL ~2 minutes (system-enforced expiry option set).
