# Validation audit: Profile credential SSH vault vs plan

**Date:** 2026-05-15  
**Re-validated:** 2026-05-15 — ChatView composer fixes applied; `xcodebuild` green (see Section B).
**Based on:** Vault validation checklist (`vault_validation_checklist_85049a82`) and original feature plan (`profile_credential_ssh_vault`).  
**Scope:** Static traceability (Section A), automated gate (Section B), security review checklist (Section C), manual QA script (Section E). The validation plan file under `.cursor/plans/` was **not** edited.

---

## Summary

| Area | Result |
|------|--------|
| **Section A** (requirement traceability) | **PASS** — each plan row maps to concrete code or docs (see table below). |
| **Section B** (build + logging grep) | **PASS** — `xcodebuild` succeeds (iPhone 17 / iOS 26.2 simulator). No `print` in `AdvancedTools.swift`. |
| **Section C** (security / product) | **PASS** on static review; confirm clipboards and error strings in UI on device. |
| **Section E** (original plan §6) | **PARTIAL** — Items **1, 2, 4, 5** verified by **code path + build** (below). Items **3** and **6** need a **real SSH lab host** and device/simulator smoke (operator). |

---

## Section A — Traceability matrix (evidence)

| Check | Verdict | Evidence |
|-------|---------|----------|
| Keychain CRUD, account names | PASS | [`CredentialVault.swift`](../Whetstone/Auth/CredentialVault.swift): `password.<uuid>`, `sshPrivateKey.<uuid>`, `SecItemAdd` |
| Accessibility + no iCloud keychain sync | PASS | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable: false` |
| UserDefaults index only metadata | PASS | `defaultsKey = "whetstone.vault.index"`, `VaultMetadataIndex` Codable |
| Models `allowAgentUse`, SSH `publicKeyDisplay` | PASS | `VaultPasswordEntry`, `VaultSSHIdentity` |
| Profile visibility gate | PASS | [`ProfileView.swift`](../Whetstone/Auth/ProfileView.swift) `vaultVisible = auth.isAdvancedUser && agentModeStore.mode == .advanced` |
| ScrollView | PASS | `ScrollView {` wraps main column |
| Sheets + pasteboard TTL | PASS | `UIPasteboard` `.expirationDate`: 300s (plain id), 120s (secret path) |
| `ssh_execute` auth exclusivity | PASS | [`AdvancedTools.swift`](../Whetstone/AI/AdvancedTools.swift) `modes == 1` guard |
| `allowAgentUse` enforces tool resolution | PASS | `CredentialVaultStore.sshPasswordSecretForAgentUse` / `sshPrivateKeyPEMForAgentUse` check `allowAgentUse` |
| No `print` on SSH / vault path | PASS | `grep print(` in `AdvancedTools.swift` → **no matches** |
| Tool output = remote text + errors only | PASS | `ConversationStore` appends `Message.toolResult(..., content: result.output)` — resolved secrets not concatenated into user-visible path except Citadel return / error strings |
| Ed25519/RSA + passphrase | PASS | `SSHKeyDetection` + `Curve25519.Signing.PrivateKey(sshEd25519:)` / `Insecure.RSA.PrivateKey(sshRsa:)`, dict `key_passphrase` |
| Default SSH username from vault | PASS | `CredentialVaultProviding.defaultUsernameForSSHIdentity`, `resolveSSHUsername` async path |
| Advanced prompt vault guidance | PASS | [`advanced_system_prompt.txt`](../Whetstone/Resources/advanced_system_prompt.txt) mentions `saved_password_id` / `saved_ssh_identity_id` |
| Standard prompt unchanged | PASS | [`system_prompt.txt`](../Whetstone/Resources/system_prompt.txt) has **no** `vault` / `saved_password` |
| Xcode target | PASS | `CredentialVault.swift` in `project.pbxproj` Sources + Auth group |
| Journal doc | PASS | [`profile-credential-vault.md`](profile-credential-vault.md) |
| Vault only when Advanced snapshot | PASS | `credentialVault: advancedToolsEnabledSnapshot ? credentialVaultStore : nil` in [`ConversationStore.swift`](../Whetstone/Conversation/ConversationStore.swift) |
| App + Profile wiring | PASS | [`WhetstoneApp.swift`](../Whetstone/WhetstoneApp.swift), [`ChatView.swift`](../Whetstone/Chat/ChatView.swift) `.environmentObject(credentialVaultStore)` on Profile sheet |
| `dispatchToolCall` | PASS | [`MentorTools.swift`](../Whetstone/AI/MentorTools.swift); call sites: **ConversationStore** (passes vault); **ChatViewModel** (`advancedToolsEnabled: false`, default `credentialVault: nil`) |
| `http_request` + saved password (follow-up) | N/A | **Not implemented** (per plan optional); no stray `saved_password` on `http_request` |

**Minor plan nuance:** Key type “hint” in metadata is implemented as optional **`publicKeyDisplay`** (user-pasted) rather than auto fingerprint — consistent with plan v1.

---

## Section B — Build gate

**Command run:** `xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build`

**Result:** **PASS** (`BUILD SUCCEEDED`).

**Logging grep:** `AdvancedTools.swift` contains **no** `print(` calls (no accidental vault/SSH secret logging).

**Unrelated fix applied during validation (composer):** [`ChatView.swift`](../Whetstone/Chat/ChatView.swift) — `PastableTextEditor` expected `Binding<Bool>` for focus but call sites used `@FocusState` projections. Bridged with `Binding(get:set:)` for `editFieldFocused` and `inputFocused`. **`updateUIView`** called `context.coordinator.parent.applyFocus` but `applyFocus` lives on **`Coordinator`** — corrected to `context.coordinator.applyFocus(tv:)`. These issues blocked Section B; they are **not** part of the vault feature.

**Target membership:** `CredentialVault.swift` remains only in the Whetstone app target (per `project.pbxproj`).

---

## Section C — Security / product (static)

| Item | Notes |
|------|--------|
| Clipboard TTL | Implemented; UI copy line references ~2 min for password copy. |
| Copy ignores `allowAgentUse` | Confirmed: `passwordSecretForClipboard` bypasses flag — matches plan “Profile still allows copy.” |
| `@MainActor` vault protocol | `CredentialVaultProviding` + `CredentialVaultStore`; tools use `await` to vault. |
| `entryNotFound` vs `agentUseNotAllowed` | Different `CredentialVaultError` strings; acceptable for telemetry; verify wording is not confusing in tool output. |

---

## Section E — Manual checklist (original plan §6)

### Build prerequisite (follow-up)

[`ChatView.swift`](../Whetstone/Chat/ChatView.swift) composer issues that previously blocked validation are **resolved**:

- **`PastableTextEditor`:** `isFocused` uses `Binding(get:set:)` bridging **`@FocusState`** → `Binding<Bool>` (edit + main composers).
- **`updateUIView`:** invokes **`context.coordinator.applyFocus(tv:)`** (not `parent.applyFocus`).

**Build:** `xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build` → **BUILD SUCCEEDED** (re-run after any Chat changes).

---

### Section E status

| Step | Scenario | Automated / code verification | Live device + SSH lab |
|------|-----------|-------------------------------|-------------------------|
| **1** | Advanced off **or** not entitled → **no vault UI** | **PASS** — [`ProfileView.swift`](../Whetstone/Auth/ProfileView.swift) `vaultVisible` = `auth.isAdvancedUser && agentModeStore.mode == .advanced`; vault block is `if vaultVisible { … }`. | Recommended: toggle Standard / disable entitlement once in Simulator. |
| **2** | `allowAgentUse` **off** → `saved_password_id` fails tools | **PASS** — [`CredentialVault.swift`](../Whetstone/Auth/CredentialVault.swift) `sshPasswordSecretForAgentUse` / `sshPrivateKeyPEMForAgentUse` **`guard meta.allowAgentUse`** → `CredentialVaultError.agentUseNotAllowed`; tool surfaces `LocalizedDescription`. Adv mode still passes **`credentialVault`** only when advanced snapshot ([`ConversationStore.swift`](../Whetstone/Conversation/ConversationStore.swift)). | Optional: confirm error string in transcript once. |
| **3** | `allowAgentUse` **on** → SSH password succeeds | Requires reachable host + valid creds | **Operator:** run against your test VPS. |
| **4** | Delete entry → Keychain cleaned | **PASS** — `deletePassword` / `deleteSSHIdentity` call **`CredentialVaultKeychain.delete…`** then remove from array + **`saveIndex()`**. | Optional: delete in UI, relaunch app, confirm row stays gone. |
| **5** | Restart → entries persist | **PASS** — `CredentialVaultStore.init` → **`loadFromDiskIfNeeded()`** decodes **`whetstone.vault.index`**; secrets re-read from Keychain on use. | Optional: cold-restart Simulator app. |
| **6** | Key PEM + optional `key_passphrase` | Same as (3) + key material | **Operator:** Ed25519/RSA lab host; test encrypted PEM if used. |

---

## Sign-off checklist (validation plan §E)

- [x] Section A rows checked (above).
- [x] Section B build green.
- [x] Section C static review documented.
- [x] Section E — **static / code-path** items **1, 2, 4, 5** verified (table above).
- [ ] Section E — **SSH integration** items **3, 6** (and optional UI smoke for 1, 4, 5) when a lab host is available.

**Operator:** When you have SSH infrastructure, complete the remaining checkboxes on device and note the date here: ___.
