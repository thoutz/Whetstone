# Thinking slashes: ScrollView, animation, and TimelineView

**Date:** 2026-05-15  
**Scope:** In-chat `ThinkingSlashes` in [`Whetstone/Chat/ChatView.swift`](../Whetstone/Chat/ChatView.swift).

## Symptom

Three `/` characters in the “thinking” row often appeared **static** even after:

- Using view-level `.opacity` (not only `foregroundStyle(Color.opacity(...))`), and
- Matching **`WhetstoneTheme.blade`** to `HoningDots`.

Console showed **`AttributeGraph: cycle detected`** and **`Bound preference ChatTranscriptBottomKey tried to update multiple times per frame`** during chat use.

## What the logs mean (short)

| Log | Relevance |
|-----|-----------|
| `Reporter disconnected`, `gesture gate timed out`, `Reading from … user settings` | Usually Simulator / Xcode noise; not root cause for slashes. |
| `UITextView … TextKit 1 compatibility` | Rich text / markdown hosts; unrelated to slash drawing. |
| `AttributeGraph: cycle detected` | SwiftUI dependency graph cycle; can make updates and implicit animation **unreliable** in the same subtree. |
| `ChatTranscriptBottomKey … multiple times per frame` | Geometry + scroll: bottom anchor fires more than once per frame; already mitigated with deferred `DispatchQueue.main.async` in `onPreferenceChange` (see [simulator-console-noise-and-chatview-fixes.md](./simulator-console-noise-and-chatview-fixes.md)). |

## Research summary

1. **`withAnimation` / `repeatForever` inside `ScrollView`**  
   Common reports that scroll-driven layout and implicit animations interact badly (e.g. [SwiftUI Animation Bug inside Scroll View](https://stackoverflow.com/questions/67530768/swiftui-animation-bug-inside-scroll-view), [withAnimation in ScrollView](https://stackoverflow.com/questions/65152436/swiftui-how-to-use-withanimation-in-a-scrollview)). Not every case fails, but **transcript rows are a worst case**: `LazyVStack`, auto-scroll, and preference keys.

2. **`TimelineView`**  
   Apple documents `TimelineView` as a container that **re-evaluates its content on a schedule** ([TimelineView](https://developer.apple.com/documentation/swiftui/timelineview)). The SwiftUI Lab series frames it as the right tool for **time-driven** visuals that need periodic refresh ([Advanced SwiftUI Animations — Part 4: TimelineView](https://swiftui-lab.com/swiftui-animations-part4/)).  
   Here we use `TimelineSchedule.animation(minimumInterval:paused:)` (~30 Hz) so opacity derives from **wall-clock phase** `(date / 1.2).truncatingRemainder(1.0)`—same 1.2s cycle and sine formula as `HoningDots`, without driving a `@State Double` through the repeat-forever animation pipeline.

3. **Why not fix “cycles” first?**  
   Reducing AttributeGraph cycles in the full chat stack (preferences, jump-to-latest, keyboard) is a larger pass. **Clock-driven slashes** are localized, low risk, and **do not depend** on animation interpolation of `phase` completing under graph stress.

## Implementation (current)

- **`ThinkingSlashes`:** `TimelineView(.animation(minimumInterval: 1/30, paused: false))` → `phase` from `context.date` → per-slash `.opacity(slashOpacity(phase:index:))`, solid `WhetstoneTheme.blade`.
- **Lifecycle:** The view only exists while `store.isThinking` shows `ThinkingRow`, so the schedule is not left running when idle.
- **HUD `HoningDots`:** Still uses `withAnimation` + shapes; lives outside the transcript stack and has been fine.

## Verification

1. Run Simulator → send a message → confirm **blue `/ / /` pulse in a wave** for the full thinking duration.  
2. Optionally: Xcode symbolic breakpoint `AttributeGraph` / `print_cycle` if chasing remaining cycles (separate task).

## Resolution (verified)

**2026-05-15:** Confirmed in-app after switching to `TimelineView`—the in-transcript slashes animate reliably for the full thinking state (`blade` color, wave opacity). `withAnimation` + `@State phase` remained unreliable in this `ScrollView` / preference-key environment even after view-level `.opacity`.

## References

- [TimelineView | Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/timelineview)  
- [Advanced SwiftUI Animations — Part 4: TimelineView (SwiftUI Lab)](https://swiftui-lab.com/swiftui-animations-part4/)  
- [SwiftUI Animation Bug inside Scroll View (Stack Overflow)](https://stackoverflow.com/questions/67530768/swiftui-animation-bug-inside-scroll-view)  
- [How do I debug SwiftUI AttributeGraph cycle warnings? (Stack Overflow)](https://stackoverflow.com/questions/62869586/how-do-i-debug-swiftui-attributegraph-cycle-warnings)
