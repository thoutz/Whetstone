# Chat UX: copy/share row, thinking row, edit message, clipboard paste

**Date:** 2026-05-15  

## Summary

Implemented four chat UX changes in **Whetstone**:

1. **Copy + Share** — `doc.on.doc` sits **beside** `square.and.arrow.up` in one trailing `HStack` at the bottom of each mentor/tool row (`MentorMessageView`).
2. **In-transcript “Thinking”** — When `ConversationStore.isThinking` is true, a `ThinkingRow` (blade rail + label + existing `HoningDots`) renders after the transcript; scrolling targets `thinking-anchor` then snaps to `bottom` when thinking ends.
3. **Edit user message** — Long-press any user bubble → **Edit message** → replacement composer replaces the normal input bar. On **Send**, `ConversationStore.editMessage` truncates `messages`/`apiHistory` from that student turn onward and calls `send` with updated text/images.
4. **Paste image (and text)** — Main and edit composers use `PastableTextEditor` (`PastingComposerTextView` overriding `paste(_:)`) → clipboard **image** JPEG (via existing `AttachmentEncoder`) appends into staged thumbnails; clipboard **text** falls through `super.paste`.

## Files changed

| File | Change |
|------|--------|
| [Whetstone/Chat/ChatView.swift](Whetstone/Chat/ChatView.swift) | `PastableTextEditor`, `ThinkingRow`, `editMessageComposer`, `MessageRow`/`UserMessageView` signatures, mentor action row layout, keyboard inset includes `editFieldFocused`, paste handling |
| [Whetstone/Conversation/ConversationStore.swift](Whetstone/Conversation/ConversationStore.swift) | `editMessage(id:newText:newImages:)` |
| [Whetstone/Chat/ChatMessage.swift](Whetstone/Chat/ChatMessage.swift) | `isUserTurn` helper |

No new SPM packages. No plist changes.

## Behaviour notes

### `editMessage` / API alignment

- Counts student turns *before* the edited bubble in **`messages`** to find the matching **Nth** `.user` entry in **`apiHistory`** (skipping leading `.system`, tools, assistants).
- Computes the cut index **before** mutation; aborts (`return`) if no matching API user turns (corrupt divergence).
- `newImages` empty → retains the edited message’s `attachedImages`; non-empty replaces them.
- `send` still handles context-limit fork (`forkIntoNewConversation`) and clears chip offers like a normal send.

### Paste precedence

When the clipboard has a raster image, **image paste attaches** it and **does not** insert text from the pasteboard in that action. Mixed clipboard content is ambiguous; revisit if dual insert is desired.

### Focus / keyboard hook

`ComposerAsciiKeyboardHook` remains a sibling of the composer; it still resolves a nearby `UITextView` and forces `.asciiCapable` when focused. `pastable` updates also reset `keyboardType` on layout passes.

### Composer height + stable typing (2026 update)

**Height:** [`PastableTextEditor`](Whetstone/Chat/ChatView.swift) reports clamped intrinsic height into `@State composerContentHeight` / `editComposerContentHeight` (see `ComposerTextMetrics`: min ~one line, max 120 pt). Inner `UITextView` scrolling is enabled only when content exceeds max height. Width-driven remeasure uses `layoutSubviews` via `onBoundsChange` so empty state stays short.

**Typing / scroll churn:** Keyboard frame notifications only bump transcript `scrollTo("bottom")` when overlap **first becomes significant** (`lastKeyboardOverlapForScroll < 0`) or shifts by **&gt; 18 pt** — avoids slamming [`transcriptScrollToBottomTick`](Whetstone/Chat/ChatView.swift) on each sub-pixel animation. [`PastableTextEditor`](Whetstone/Chat/ChatView.swift) calls `applyFocus` only when focus, enabled, or `composerKeyboardHookTick` **actually changes**, and uses a **programmatic resign** guard so [`textViewDidEndEditing`](Whetstone/Chat/ChatView.swift) does not clear `@FocusState` when we resign intentionally. Chat [`ScrollView`](Whetstone/Chat/ChatView.swift) uses [`scrollDismissesKeyboard(.never)`](Whetstone/Chat/ChatView.swift) so programmatic scroll doesn’t fight interactive keyboard dismiss.

Common Xcode console noise (`nw_connection…`, `Reporter disconnected…`) remains unrelated unless paired with reproducible traces.

### CSS

N/A (SwiftUI / UIKit chat surface only.)

## Verification

- Xcode: Build **Whetstone** target.
- Mentor row: Copy and Share icons appear together on replies with shareable prose or diagram caption.
- Send a prompt: “Thinking…” row appears; HUD dots remain.
- Long-press a user bubble → edit → Cancel / Send.
- Copy an image, focus composer → Paste → thumbnail appears under toolbar (respect max 4).
- Composer starts **one line** tall; grows with text; pasted images unchanged in strip UX.
- Type continuously: transcript should **not** “run away”; keyboard stays up (no scroll-dismiss).

## Follow-ups (optional)

- Token gauge does not rewind when history is truncated (only display state changes).
- If pasteboard image + text insertion in one gesture is required, orchestrate sequential `UIPasteboard` reads after image attach.
