# Copy mentor response controls

**Date:** 2026-05-13  
**Goal:** Make it easy to copy mentor/tool replies from the transcript without relying on obscure text-selection gestures.

## Behavior

| Situation | Clipboard contents | Context menu title | Copy icon |
|-----------|-------------------|-------------------|-----------|
| Non-empty `ChatMessage.text` | Full `message.text` (raw markdown/source as stored) | Copy response | Shown |
| Empty text, non-empty `svgPayload.caption` | Raw caption string | Copy caption | Shown |
| Empty text and no usable caption | — | No menu actions | Hidden |

- **`HONED` meta** and **SVG markup** are never copied.
- **Existing** `.textSelection(.enabled)` on [`MentorMarkdownView`](Whetstone/Chat/MentorMarkdownView.swift) is unchanged for partial selection when desired.

## UI

Implemented in [`ChatView.swift`](Whetstone/Chat/ChatView.swift) on **`MentorMessageView`** (covers `.mentor` and `.tool` roles):

1. **Context menu** — Long-press the mentor content column (markdown / diagram / meta stack), not the blade rail.
2. **Visible affordance** — `doc.on.doc` beside the column; idle opacity ~0.35 white, **blade** color while pressed (`MentorCopyAffordanceStyle`).
3. **Feedback** — `sensoryFeedback(.success, trigger:)` bumps when pasteboard write succeeds (iOS 17+).

Accessibility:

- Label: **Copy response** or **Copy caption** depending on payload.
- Hint differs for prose vs caption-only rows.

## Implementation notes

- `UIPasteboard.general.string` is used; UIKit was already imported in `ChatView.swift`.
- `xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeded after the change.

## Manual QA checklist (device/simulator)

1. Message with markdown — Copy → paste elsewhere preserves markdown characters.
2. Diagram-only turn with caption — Only **Copy caption** appears; pasted text matches caption.
3. VoiceOver — Focus copy button; confirm label/hint; context menu via long-press.

## Follow-ups (out of scope)

- Copy user bubbles; per–code-fence copy; share sheet; rich HTML paste.
