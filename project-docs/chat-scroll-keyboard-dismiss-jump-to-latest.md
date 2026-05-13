# Chat: Scroll Dismisses Keyboard + Jump to Latest + Keyboard Inset

**Date:** 2026-05-11 (updated with keyboard-inset pass)  
**Scope:** Transcript UX aligned with common chat apps—scroll vs keyboard, jump to latest, and last message visible while typing.

## Behavior

1. **Keyboard + scroll:** The transcript `ScrollView` uses [`.scrollDismissesKeyboard(.interactively)`](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)) in [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift). Interactive dismissal tracks the gesture so small corrective scrolls while composing are less harsh than `.immediately`. The root drawer swipe uses [`.simultaneousGesture`](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:including:)) in [`DrawerContainer`](../Whetstone/Conversation/SidebarView.swift) so vertical list scrolling is not starved by a parent `DragGesture`.

2. **Keyboard inset (tail of last reply visible):** `keyboardWillChangeFrame` / `keyboardWillHide` update `@State keyboardBottomInset` (intersection of the keyboard frame with the key window). While the composer is focused and the keyboard is up, the transcript `LazyVStack` gains **extra bottom padding** (`20 + keyboardBottomInset`) so the thread can scroll enough to keep the **bottom of the latest mentor message** (e.g. HONED line) above the composer. Focus and keyboard-frame changes bump `transcriptScrollToBottomTick` / call `scheduleTranscriptScrollToBottom` to `scrollTo("bottom")` after layout (async + short delayed pass for keyboard animation).

3. **Jump to latest:** When the student scrolls **up** to read history, a **circular down chevron** appears bottom-trailing over the message list. Tapping it scrolls to the `"bottom"` anchor. The control hides when aligned with the bottom, on send auto-scroll, or when switching conversations.

## Implementation notes

- **UserInfo key:** `UIResponder.keyboardFrameEndUserInfoKey` (not legacy `UIKeyboardFrameEndUserInfoKey`) for keyboard frame in notifications.
- **iOS 17–safe geometry:** Preference keys for jump-to-latest (`ChatScrollViewportBottomKey`, `ChatTranscriptBottomKey`) unchanged.
- **Layer 2 (plan):** `.interactively` chosen after keyboard inset so users can nudge content without instant full dismiss where possible; if a future product requirement needs “dismiss only when scrolling up,” that would require a UIKit `UIScrollViewDelegate` bridge.

## Files

- [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift) — keyboard notifications, transcript padding, scroll-to-bottom on focus + keyboard frame, scroll-dismiss mode, preference keys, jump button.
- [`Whetstone/Conversation/SidebarView.swift`](../Whetstone/Conversation/SidebarView.swift) — `DrawerContainer` uses `simultaneousGesture`.
- This journal — `project-docs/chat-scroll-keyboard-dismiss-jump-to-latest.md`

## Verification

- Build: `xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build`.
- Manual: after a **long** mentor reply, tap composer—full tail of reply visible without manual scroll; scroll history with keyboard dismissed; scroll with keyboard up—interactive dismiss; jump chip when scrolled up.
