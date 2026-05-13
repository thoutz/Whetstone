# Chat markdown formatting upgrade

**Date:** 2026-05-12  
**Goal:** Replace plain mentor/tool transcript text with structured markdown rendering (paragraph spacing, headings, lists, code, horizontal rules, bold/italic) so replies read less “flat terminal” and closer to polished chat UIs—without adding SPM dependencies.

## What was implemented

### New file

- [`Whetstone/Chat/MentorMarkdownView.swift`](../Whetstone/Chat/MentorMarkdownView.swift) — public `MentorMarkdownView(text:)` plus private block + inline parsers.

### Integration

- [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift) — `MentorMessageView` now uses `MentorMarkdownView(text: message.text)` instead of raw `Text(message.text)`. User bubbles, blade rail, SVG diagrams, and `HONED` meta row unchanged.

### Xcode project

- [`Whetstone.xcodeproj/project.pbxproj`](../Whetstone.xcodeproj/project.pbxproj) — added `MentorMarkdownView.swift` to the **Chat** group and **Compile Sources** (IDs `AA00000000000000000000DB` / `AA00000000000000000000DC`).

### Docs

- [`CLAUDE.md`](../CLAUDE.md) — source layout lists `MentorMarkdownView.swift`.

## Rendering behavior

| Feature | Implementation notes |
|--------|----------------------|
| Paragraph breaks | Input split on blank lines (`\n\n`); soft line breaks inside a block joined with spaces. |
| `#` … `######` headings | Single-line headings; sizes 20 / 18 / 15 pt semibold by level; extra top padding for larger headings. |
| `---` (etc.) rules | Line of only `-`, `*`, or `_` (≥3 chars). |
| Bullet lists | Consecutive `- ` / `* ` lines → ember bullet + inline markdown per row. |
| Numbered lists | Consecutive `n. ` lines → blade monospaced index + inline markdown. |
| Fenced code | ``` … ``` blocks → `surface` fill, blade stroke, horizontal scroll, monospaced body text. |
| **Bold** / *italic* | `AttributedString(markdown:…inlineOnlyPreservingWhitespace)` then run normalization for SF weights/opacities. |
| `` `inline code` `` | Split on backticks first; code runs use monospaced blade text + `surfaceHigh` **background** via `AttributedString.backgroundColor` (single `Text`, preserves wrapping). |

## Implementation notes / quirks

1. **`Text` + modifiers:** Concatenating `Text` with `.padding`/`.background` breaks type (`Text` + `some View`). Inline code styling was moved entirely into one `AttributedString` (`attributedParagraph`) so wrapping stays correct.

2. **`Equatable` on blocks:** A `MarkdownBlock` case carried `[(index:text:)]` tuples; Swift did not synthesize `Equatable`, so the enum does **not** conform to `Equatable` (not required for the UI).

3. **Build verification:** `xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeded after the above fixes.

## Follow-ups (optional)

- Teach `system_prompt.txt` to use markdown deliberately (headings/lists) when it helps scanability—behavioral, not required for this UI change.
- Headings do not yet split `` `code` `` spans separately from body paragraphs (headings use markdown parsing only on the full title string).
