# Tappable response chips — implementation journal

**Date:** 2026-05-11  
**Scope:** `render_chips` tool, ephemeral UI strip, standing “I'm stuck” affordance.

## Summary

- Added second mentor tool **`render_chips`** with JSON-schema arguments: `chips[]` (`label`, `value`), `allow_multi_select`, `include_other`.
- **`ConversationStore`** owns **`pendingChipOffer`** (`conversationId` + `ChipsPayload`) so sidebar switches never show another thread’s chips.
- **`send(_:)`** clears the offer at the top; **`select`** / **`newConversation`** clear it.
- **`runLoop`** breaks after a turn that emits chips (waits for user reply before another completion).
- **`ChatView`**: horizontal **`ChipsStrip`** above the input bar; **Other** calls **`dismissChipOfferForOther()`** and focuses the text field (no message).
- Chip tap calls **`store.send(chip.label)`** so **`apiHistory`** stays human-readable.
- Input bar: persistent low-prominence **I'm stuck** sends a fixed user string.
- **`system_prompt.txt`**: new `# Tappable responses` section (when/how to use chips, over-emission warning).
- **`CLAUDE.md`**: layout + design decisions + chips policy section; hard rules now list both tools.

## Files touched

| File | Change |
|------|--------|
| `Whetstone/AI/MentorTools.swift` | `Chip`, `ChipsPayload`, `renderChips` tool, `ToolResult.chipsPayload`, `handleRenderChips` |
| `Whetstone/Conversation/ConversationStore.swift` | `PendingChipOffer`, `visibleChipPayload`, clear/dismiss APIs, loop break on chips |
| `Whetstone/Chat/ChatView.swift` | `ChipsStrip`, `chipStripSection`, I'm stuck button |
| `Whetstone/Resources/system_prompt.txt` | Tappable responses guidance |
| `CLAUDE.md` | Docs sync |

## CSS / styling

N/A (SwiftUI). Chips use existing tokens: `WhetstoneTheme.surfaceHigh`, `WhetstoneTheme.blade` stroke, `Capsule`, monospaced labels.

## Verification

- `xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**.

## Deferred

- Multi-select UI when `allow_multi_select == true` (Phase 1 = single tap only; flag parsed and stored).
