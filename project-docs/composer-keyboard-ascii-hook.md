# Composer ASCII keyboard hook

Date: 2026-05-11  

## Problem

After the first mentor reply (and similar chat updates), the multiline composer sometimes reopened with the **numbers/symbols** keyboard plane even though SwiftUI used `.keyboardType(.asciiCapable)`. Multiline `TextField(axis: .vertical)` bridges to **`UITextView`**; UIKit can persist the wrong keyboard subtype across updates.

## Change

**File:** `Whetstone/Chat/ChatView.swift`

- Added `@State private var composerKeyboardHookTick` incremented when:
  - `store.messages.count` changes,
  - `store.isThinking` becomes `false`,
  - `inputFocused` becomes `true`.
- Added **`ComposerAsciiKeyboardHook`** (`UIViewRepresentable`): when the composer is focused, finds the nearby **`UITextView`/`UITextField`**, sets **`keyboardType = .asciiCapable`**, calls **`reloadInputViews()`**.
- Removed temporary **debug NDJSON / AGENTDBG** instrumentation from the keyboard investigation.

**Related:** `render_chips` Groq validation fix remains in `MentorTools.swift` (`anyOf` boolean|string + `mentorBool` coercion).
