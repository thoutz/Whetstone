# Keyboard: Symbols/Numbers Plane After Send — Fix

**Date:** 2026-05-11  
**Issue:** After sending chat messages (e.g. “what can i change now to improve this?”), the system keyboard sometimes stayed on or returned to the **numbers/symbols** plane instead of the alphabetic layout.

## Root cause (summary)

- `ComposerAsciiKeyboardHook` in [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift) set `keyboardType = .asciiCapable` and then called **`reloadInputViews()`** on the bridged `UITextView` / `UITextField`.
- `reloadInputViews()` forces a full keyboard / input accessory rebuild. iOS does not guarantee the **alphabetic** plane after that rebuild—the symbols plane can remain active.
- `composerKeyboardHookTick` was incremented on **`store.messages.count`**, so every new message (user or mentor) re-ran the hook while focus could still be on the composer, amplifying the problem.
- `send()` cleared `draft` twice (immediate + `DispatchQueue.main.async`), adding extra binding churn around submit.

**Note:** Xcode logs mentioning `FigCaptureSourceRemote` / `FigXPCUtilities` relate to **camera capture**, not keyboard state.

## Implementation (what changed)

All edits in [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift).

1. **`ComposerAsciiKeyboardHook.updateUIView`**  
   - Still sets `keyboardType = .asciiCapable` on the resolved text input.  
   - **Removed** all `reloadInputViews()` calls.  
   - Extended doc comment: avoid `reloadInputViews()` because it can leave the keyboard on the symbols plane.

2. **`composerKeyboardHookTick` observers**  
   - **Removed** `.onChange(of: store.messages.count)` that incremented the tick.  
   - **Kept** tick bumps when `isThinking` becomes `false` and when `inputFocused` becomes `true`.

3. **`send()`**  
   - **Removed** the `DispatchQueue.main.async { draft = "" }` second clear (and the old comment about multiline `TextField` re-applying the binding).

## Verification

- **Automated:** `xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build` — **succeeds** (exit code 0).
- **Manual (recommended):** In Simulator or on device, send a message, wait for the mentor reply, and confirm the keyboard stays on the **ABC** layout when continuing to type. If the plane still flips rarely, the plan’s fallback was to briefly cycle `keyboardType` (`.default` → `.asciiCapable`) without `reloadInputViews()`.

## Installation

No new dependencies; standard Xcode build of the Whetstone target.
