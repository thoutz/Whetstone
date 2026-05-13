# Keyboard jumped to numbers/symbols after send

**Date:** 2026-05-11

## Symptom

After sending a chat message, the software keyboard sometimes switched to the **numbers / symbols** plane instead of staying on letters.

## Likely causes

1. **Multiline `TextField(axis: .vertical)`** uses SwiftUI’s vertical text path (`UITextView`). Combined with **submit** + clearing text, internal keyboard state can glitch on some iOS versions (related feedback around `VerticalTextView` / return handling).
2. **Programmatic scroll** when `messages.count` changes might interact with the default scroll keyboard dismissal behavior and leave the keyboard in an odd mode.

## Mitigations (ChatView)

In [`ChatView.swift`](Whetstone/Chat/ChatView.swift):

- Composer: **`.keyboardType(.default)`** and **`.textInputAutocapitalization(.sentences)`** so the field stays on the normal typing keyboard contract.
- Message **`ScrollView`**: **`.scrollDismissesKeyboard(.never)`** so auto-scroll-to-bottom after send does not participate in keyboard-dismiss machinery that can confuse layout.
- Composer: stable **`.id("whetstoneChatComposerField")`** to reduce unnecessary recreation of the control during parent updates.

Existing **deferred `draft` clear** (`DispatchQueue.main.async`) after send remains for the separate “text stuck in field” fix.

## Follow-up

If the issue persists on a specific iOS build, next step would be a small **UIKit `UITextView` wrapper** with explicit `keyboardType` / `reloadInputViews()`, or replacing multiline `TextField` with **`TextEditor`** styled like the composer.
