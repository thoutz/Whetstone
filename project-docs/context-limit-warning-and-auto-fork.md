# Context limit: warning banner + auto-fork on send

**Date:** 2026-05-12  
**Scope:** Option A — proactive UI when the HUD context gauge reaches **80%**. Option B — when the gauge reaches **95%**, the next user send starts a **new conversation** with a short transcript handoff so the API is less likely to reject long payloads.

## Background

The HUD percentage ([`ConversationStore.contextFraction`](../Whetstone/Conversation/ConversationStore.swift)) compares rolling [`Conversation.totalTokensUsed`](../Whetstone/Conversation/Conversation.swift) (sum of API `usage.totalTokens` per completion) to [`WhetstoneTheme.contextWindowTokens`](../Whetstone/WhetstoneTheme.swift) (128k assumption). Previously there was no client-side guard before the provider returned context-length errors.

## Behavior

1. **Warning (≥ 80%, &lt; 95%):** A slim banner appears **above the input bar** with copy *“Conversation is nearing its limit”*, a **New chat** button (`ConversationStore.newConversation()`), and **dismiss** (×). Dismiss is tracked locally in `ChatView` via `@State contextLimitBannerDismissed` and resets when `store.activeId` changes.

2. **Auto-fork (≥ 95%):** On `send(...)`, if `isAtContextLimit` is true, the app does **not** append the message to the full thread. It calls `forkIntoNewConversation(...)`: snapshots the **last 6** [`ChatMessage`](../Whetstone/Chat/ChatMessage.swift) rows as plain lines (`Student:` / `Mentor:` / `[Diagram]` / `[Photo attached]`), calls `newConversation()`, prepends one `.system(...)` handoff message to the new thread’s `apiHistory`, then appends the user turn (display + API multimodal) like a normal send and runs `runLoop` on the new conversation id. Remote sync uses existing `scheduleCreateRemote` / persist paths.

## Thresholds (tunable)

Defined as private statics on `ConversationStore`:

- `contextLimitWarnFraction = 0.80`
- `contextLimitForkFraction = 0.95`
- `contextLimitHandoffLineCount = 6`

## Files

- [`Whetstone/Conversation/ConversationStore.swift`](../Whetstone/Conversation/ConversationStore.swift) — `isNearContextLimit`, `isAtContextLimit`, `shouldOfferContextLimitBanner`, `forkIntoNewConversation`, `handoffTranscript`, branch in `send`.
- [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift) — `contextLimitBannerSection`, `ContextLimitBanner`, animation value, `onChange(of: store.activeId)` to reset dismiss flag.

## Verification

- Build: `xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build`.
- Manual: simulate high `totalTokensUsed` or wait for a long session — banner between 80–95%; at ≥95% send lands in a **new** sidebar thread with prior snippet in API history only (not as duplicate UI bubbles in the old thread).
