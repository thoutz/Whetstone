# Markdown transcript formatting v2

**Date:** 2026-05-13  
**Goal:** Improve readability when the model emits numbered steps inline (`1. … 2. …` on one line), and reinforce real Markdown lists via the system prompt. Builds on [`MentorMarkdownView.swift`](Whetstone/Chat/MentorMarkdownView.swift) and [`chat-markdown-formatting-upgrade.md`](chat-markdown-formatting-upgrade.md).

## 1. System prompt — [`Whetstone/Resources/system_prompt.txt`](Whetstone/Resources/system_prompt.txt)

New section **# Chat formatting (Markdown)** after **# Voice**:

- Numbered steps one per line; blank line before a list after a lead-in.
- Bullets with `- `.
- Optional `##` / `###` and sparing `---`.
- Explicit anti-pattern: do not pack `1. … 2. …` on one line.

## 2. Client — inline enumeration normalizer

### Pipeline (unchanged outer structure)

Fenced code blocks → blank-line chunks → `classifyChunk`. When a chunk is **not** an all-bullet / all-numbered / heading / HR block, it becomes a **joined paragraph** string; **`expandedParagraph`** runs **`expandInlineNumberedList`** before emitting a single `.paragraph`.

### Splitting algorithm

Swift Regex **does not support lookbehind**, so splitting uses:

- Forward pattern on whitespace: **`/\s+(?=\d+\.\s\S)/`** (matches a whitespace run immediately before `digits.` + space + non-whitespace).

**First-boundary suppression:** For the **first** regex match only, if the character immediately before that whitespace is ASCII letter, digit, or `_`, the boundary is **skipped**. This reduces false splits such as `step 1. Then …` while still allowing:

- `Try this. 1. Alpha 2. Beta` — punctuation before first list marker → split → preamble paragraph + numbered list.

Later boundaries (e.g. between `1. Alpha` and `2. Beta`) are **not** subject to that suppression, so multi-item inline lists still split.

### Guards

- **`expandInlineNumberedList`** returns `nil` unless there are **≥2** non-empty segments after splitting **and** either:
  - all segments are valid numbered lines → `.numbered`, or
  - first segment is **not** numbered, tail has **≥2** numbered lines → `.paragraph(head)` + `.numbered(tail)`.
- **Unbalanced backticks** (`filter { $0 == "`" }.count % 2 != 0`) → skip normalization entirely (avoid splitting inside unfinished inline code).

### Typography

- Outer block **`VStack`** spacing: **14** pt (was 12).
- **`MentorParagraphInlineView`**: **`lineSpacing(4)`** on body `Text` (headings and code blocks unchanged).

## 3. Previews

[`MentorMarkdownView.swift`](Whetstone/Chat/MentorMarkdownView.swift) includes **`#Preview("Markdown formatting fixtures")`** with strings for:

- Baseline markdown list
- Inline enumerated paragraph + preamble
- `iOS 17.2` (no match for `\d+\.\s\S` after dot — stays paragraph)
- `step 1. Then breathe.` (first boundary suppressed — expansion typically aborts)
- Unbalanced backticks — splitter skipped

## 4. Manual QA checklist

| Fixture | Expected |
|--------|----------|
| `## H\n\n1. A\n2. B` | Heading + numbered list (unchanged) |
| `Lead. 1. A 2. B 3. C` | Paragraph + numbered rows |
| `iOS 17.2 ships` | Single paragraph |
| `step 1. Only one item` | Usually single paragraph (tail &lt; 2 items) |
| Long mentor reply with real newlines | Same as before + slightly more line spacing |

## 5. Known limitations

- First-line suppression misses some edge cases (e.g. prose starting a list without punctuation before `1.`).
- No nested lists or inline `- a - b` bullet reflow in this pass.
- Clipboard copy remains raw `message.text` (see copy-mentor-response doc).
