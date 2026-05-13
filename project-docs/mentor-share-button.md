# Mentor response share button

**Date:** 2026-05-12  
**Change:** Small share control at the bottom of each mentor/tool message (plain text via system share sheet).

## Implementation

- **File:** [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift) — `MentorMessageView.mentorContentColumn`
- After markdown, optional SVG, and optional `HonedRow`, an `HStack` with leading `Spacer` shows a **`ShareLink(item: String)`** only when `resolvedCopyPayload` is non-nil (same rule as copy: reply text, or non-empty SVG caption if prose is empty).
- **Icon:** `square.and.arrow.up`, 14 pt regular — same as copy (`doc.on.doc`).
- **Style:** `MentorCopyAffordanceStyle` (muted white / blade when pressed).
- **Accessibility:** `shareAccessibilityLabel` / `shareAccessibilityHint` parallel the copy strings (“Share response” / “Share caption”).

## Build

```bash
xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17' build
```
