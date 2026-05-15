# Simulator Console Noise & ChatView Code Improvements

**Date:** May 12, 2026  
**File changed:** `Whetstone/Chat/ChatView.swift`

---

## Summary

Investigated a set of red console log entries appearing during simulator runs. Most are
iOS Simulator infrastructure noise that cannot be fixed from app code. Two were genuine
SwiftUI/UIKit warnings with actionable fixes.

---

## Error Classification

### Simulator-only noise — no code change required

These appear exclusively in the iOS Simulator because it runs without a full sandboxed
container and lacks certain system entitlements. They will **not appear** on a physical
device, TestFlight, or App Store build.

| Message | Cause |
|---|---|
| `Failed to locate container app bundle record` | LaunchServices sandbox mismatch in simulator |
| `NSOSStatusErrorDomain Code=-54 com.apple.private.coreservices.canmaplsdatabase` | Simulator lacks LaunchServices entitlement |
| `Attempt to map database failed: permission was denied` | Same as above |
| `Received port for identifier response: Client not entitled` (RBSServiceErrorDomain) | RunningBoard entitlement absent in simulator |
| `elapsedCPUTimeForFrontBoard couldn't generate a task port` | FrontBoard task port unavailable in simulator |
| `(501) personaAttributesForPersonaType failed … usermanagerd.xpc invalidated` | User management XPC not wired in simulator |
| `Error creating the CFMessagePort needed to communicate with PPT` | Predictive Processing Thread not available in simulator |
| `fence tx observer timed out` | GPU fence in simulator driver |
| `Reading from public effective user settings` | System settings read — benign |
| `Plugin query method called` | Xcode plugin host event — benign |
| `Gesture: System gesture gate timed out` | UIKit gesture arbiter simulator fidelity issue — self-resolving on device |

---

## Fix 1 — `Bound preference ChatTranscriptBottomKey tried to update multiple times per frame`

### Root cause

During keyboard animation or rapid message appends, multiple SwiftUI layout passes fire
within the same render frame. The `GeometryReader` inside the `"bottom"` spacer writes
to `ChatTranscriptBottomKey`; when that value change triggers the containing view to
resize, the reader fires again in the same frame, causing the SwiftUI runtime warning.
(Confirmed pattern from Apple engineer commentary on Developer Forums.)

### Fix applied

Wrapped both `.onPreferenceChange` handlers in `DispatchQueue.main.async {}`. This
defers the `@State` mutation to the next run loop cycle, breaking the synchronous
re-layout chain. The state update incurs at most a one-frame delay (~16ms), which is
imperceptible for a scroll-position indicator.

`DispatchQueue.main.async` is safe here because `onPreferenceChange` already runs on
the main thread — the async dispatch simply prevents the same-frame re-entry.

```swift
.onPreferenceChange(ChatScrollViewportBottomKey.self) { y in
    DispatchQueue.main.async {
        scrollViewportBottomGlobalY = y
        refreshJumpToLatestVisibility()
    }
}
.onPreferenceChange(ChatTranscriptBottomKey.self) { y in
    DispatchQueue.main.async {
        chatTranscriptBottomGlobalY = y
        refreshJumpToLatestVisibility()
    }
}
```

**Swift 6 note:** In Swift 6 strict concurrency mode, `onPreferenceChange` closures are
`@Sendable` and cannot directly mutate `@MainActor`-isolated `@State`. The
`DispatchQueue.main.async` wrapper handles this correctly without further changes.

---

## Fix 2 — `Got a keyboard will/did hide notification, but keyboard was not even present`

### Root cause

`keyboardWillHideNotification` (and occasionally `keyboardWillChangeFrameNotification`)
is fired by `scrollDismissesKeyboard(.interactively)` even when the keyboard was never
shown — e.g., when the user performs an interactive scroll drag with no text field
focused. The previous handlers unconditionally mutated `keyboardBottomInset`, causing
an unnecessary SwiftUI state update and re-render each time.

UIKit prints the warning before dispatching the notification, so the console message
cannot be eliminated from app code — but the unnecessary state churn can be prevented.

### Timing safety analysis

Using `keyboardDidShowNotification` to set a visibility flag and then gating
`keyboardWillChangeFrameNotification` on it would **break keyboard avoidance** because
`keyboardWillChangeFrameNotification` fires *before* `keyboardWillShowNotification` and
`keyboardDidShowNotification` in the show sequence. Gating it would block the initial
inset update.

### Fix applied

Added `@State private var keyboardIsVisible = false`. The flag is set to `true` inside
`keyboardWillChangeFrameNotification` when `overlap > 1` (first real keyboard frame),
and cleared in `keyboardWillHideNotification`. The hide handler is guarded by the flag
so spurious notifications are skipped without mutating state.

```swift
// New state property
@State private var keyboardIsVisible = false

// keyboardWillChangeFrameNotification handler
.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
    let overlap = Self.keyboardOverlap(from: note)
    if overlap > 1 { keyboardIsVisible = true }
    keyboardBottomInset = overlap
    if inputFocused, overlap > 1 {
        transcriptScrollToBottomTick &+= 1
    }
}

// keyboardWillHideNotification handler
.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
    guard keyboardIsVisible else { return }
    keyboardIsVisible = false
    keyboardBottomInset = 0
}
```

No new notification observers were added — the observer count stays at two.

---

## Files Changed

- `Whetstone/Chat/ChatView.swift`
  - Line ~35: added `@State private var keyboardIsVisible = false`
  - Lines ~107–118: updated `keyboardWillChangeFrameNotification` and `keyboardWillHideNotification` handlers
  - Lines ~244–255: wrapped both `onPreferenceChange` handlers in `DispatchQueue.main.async`
