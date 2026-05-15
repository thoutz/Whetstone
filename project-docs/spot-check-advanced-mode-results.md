# Spot-check results: Advanced Agent Mode

Automated/session spot-check validating **Advanced Agent Mode** against the agreed verification checklist (no plan file edits).

## 1. Artifact table (static review)

| Check | Result |
|-------|--------|
| [`Whetstone/AgentMode.swift`](../Whetstone/AgentMode.swift): `standard`/`advanced`, `bundledPrompt`, `allBundledPromptStrings`, `storageKey == "whetstone.agentMode"`, `revertToStandardIfNotEntitled` | Pass |
| [`Whetstone/Auth/SupabaseJWTHelper.swift`](../Whetstone/Auth/SupabaseJWTHelper.swift) + [`AuthManager.swift`](../Whetstone/Auth/AuthManager.swift): JWT `app_metadata.advanced_mode`, `isAdvancedUser`, `refreshEntitlementFromSession` | Pass |
| [`advanced_system_prompt.txt`](../Whetstone/Resources/advanced_system_prompt.txt) in Xcode **Resources** phase | Pass (`project.pbxproj`) |
| [`AdvancedTools.swift`](../Whetstone/AI/AdvancedTools.swift): eight tools + matching `dispatch` cases | Pass |
| Citadel SPM: package ref + Frameworks + target product dependency | Pass (`Citadel @ 0.12.1` resolved at build time) |
| [`MentorTools.swift`](../Whetstone/AI/MentorTools.swift): `dispatchToolCall(_:advancedToolsEnabled:) async`; unknown tool without advanced → `"Unknown tool: …"` | Pass |
| [`ConversationStore.swift`](../Whetstone/Conversation/ConversationStore.swift): `effectiveAgentModeForChat`, coordinated `toolsSnapshot`/`advancedToolsEnabledSnapshot`/`systemPromptBlob` in `runLoop` | Pass |
| [`ConversationPersistence.swift`](../Whetstone/Conversation/ConversationPersistence.swift): `decodeConversation(..., systemPromptVariants:)`, `Set` strip | Pass |
| [`ProfileView.swift`](../Whetstone/Auth/ProfileView.swift): toggle gated; locked copy `"Advanced Mode is available to approved users."` | Pass |
| [`ChatView.swift`](../Whetstone/Chat/ChatView.swift): HUD `ADVANCED` when `agentModeStore.mode == .advanced && auth.isAdvancedUser`; Profile sheet gets `agentModeStore` | Pass |
| [`WhetstoneApp.swift`](../Whetstone/WhetstoneApp.swift): single auth + shared `ConversationStore`; env objects + `.task` entitlement/revert | Pass |
| Docs: [`advanced-agent-mode.md`](advanced-agent-mode.md), [`CLAUDE.md`](../CLAUDE.md) | Present |

**Grep sanity:** No `decodeConversation(..., systemPrompt:)` call sites remain. All `dispatchToolCall` usages include `advancedToolsEnabled`.

## 2. Automated build

```text
xcodebuild -scheme Whetstone -destination 'generic/platform=iOS' -resolvePackageDependencies build
```

**Outcome:** Exit code **0** (graphs resolved; Citadel 0.12.1; full build succeeds on runner).

## 3. Manual scenarios A–E (code-path support + operator checklist)

Automated CI cannot sign in with Apple + Supabase for two JWT profiles. Below maps **expected UX** to the code that implements it; run these on Simulator or device after configuring test users.

| Scenario | Expected behavior | Supporting code |
|----------|-------------------|-----------------|
| **A** Non-entitled user | Toggle disabled; no badge | `ProfileView`: `.disabled(!auth.isAdvancedUser)`; HUD: badge requires `auth.isAdvancedUser` |
| **B** Entitled, Standard pref | Badge off; mentor tools only | `effectiveAgentModeForChat`: needs both advanced pref + entitlement |
| **C** Entitled + Advanced | Badge on; mentor + advanced tools | `toolsSnapshot == MentorTools.all + AdvancedTools.all`; `advancedToolsEnabledSnapshot == true` |
| **D** Revoked entitlement | Revert to Standard; badge off | `WhetstoneApp` `.task(id: auth.isAdvancedUser)` → `revertToStandardIfNotEntitled` |
| **E** Mid-session toggle | Next send picks new snapshot | Snapshots taken at **`runLoop(conversationId:)` entry** (`effectiveModeSnapshot` etc.), not cached across sends |

### Operator checklist (run locally)

1. **A:** User without `advanced_mode` in JWT → confirm Profile toggle inactive and HUD clean.
2. **B:** User with entitlement, toggle off → HUD clean; message uses standard tool list only.
3. **C:** Toggle on → HUD shows `ADVANCED`; prompt mentor to invoke e.g. `dns_lookup` or `http_request` (read-only); confirm tool rows in thread.
4. **D:** Remove `advanced_mode` in Dashboard, sign out/in → HUD off and mode forced Standard if pref was Advanced.
5. **E:** Flip toggle without new chat thread → verify next reply reflects new mode (standard vs extended tools visible in network traffic or transcript).

## 4. Conclusion

- **Repository + Xcode project:** Wired per plan; compile verified.
- **Runtime auth/chat:** Pending final confirmation via operator steps above (Simulator/device + Supabase test accounts).
