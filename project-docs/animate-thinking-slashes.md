# Animate Thinking `///` Slashes

**Date:** 2026-05-15  
**Scope:** In-chat “thinking” row while `ConversationStore.isThinking` is true.

## Goal

Replace the three rotated “honing” rectangles in the transcript thinking row with literal animated `/` characters so they visually match the `///` prefix used in `HonedRow` (“/// HONED · …”) after completions.

## Implementation

- **File:** [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift)
- **`ThinkingRow`:** Uses `ThinkingSlashes()` instead of `HoningDots()`, with `VStack` spacing `6` between the “Thinking…” label and the slashes.
- **`ThinkingSlashes`:** Pulsing **`/`** characters: monospaced medium, **`WhetstoneTheme.blade`**, same sine opacity wave as `HoningDots` (1.2s loop). **Implementation:** `TimelineView(.animation(minimumInterval: 1/30))` with phase from `context.date`—avoids `withAnimation`/`@State phase` in a `ScrollView`/`LazyVStack` where repeat-forever often stops updating under layout/preference churn (see [thinking-slashes-scrollview-animation-research.md](./thinking-slashes-scrollview-animation-research.md)).
- **Earlier attempt:** `withAnimation(.linear.repeatForever) { phase = 1 }` + `.opacity` on `Text` fixed color vs `foregroundStyle(ember.opacity)` but could still appear frozen when AttributeGraph cycles / heavy transcript updates fired.
- **HUD:** Top bar still uses `HoningDots()` (unchanged).

## Fix (animation + color)

- **Problem:** Slashes stayed static and looked orange when opacity was only inside `foregroundStyle(WhetstoneTheme.ember.opacity(...))`.
- **Fix (pass 1):** Solid `.foregroundStyle(WhetstoneTheme.blade)` plus view-level `.opacity(...)`.
- **Fix (pass 2):** Replace `@State` + `withAnimation` with **`TimelineView`** for clock-driven phase (see research doc).

## No changes

- `ConversationStore.isThinking` / scroll / accessibility label on `ThinkingRow`.
- `HonedRow` copy and styling.

## Verification

Build the Whetstone iOS target in Xcode; send a message and confirm the transcript shows three pulsing `/` characters while waiting for the mentor reply.
