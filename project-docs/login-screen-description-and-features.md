# Login Screen — Description & Feature Highlights

**Date:** 2026-05-11  
**File changed:** `Whetstone/Auth/LoginView.swift`

## What was added

A description paragraph and three feature rows were inserted between the existing wordmark block and the Sign in with Apple button area. No existing UI was modified.

### Layout (top → bottom)

1. `BladeMarkView` icon + "WHETSTONE" wordmark + "Sharpen your craft." tagline _(unchanged)_
2. **NEW — Description paragraph**  
   Centered muted-white text:  
   _"Your personal mentor for drawing, writing, music, repair, and more — built to sharpen real skill, not shortcut it."_
3. **NEW — Feature card** (`surfaceHigh` background, 16 pt rounded rect, 1 px white/7% border)
   - Row 1 — `camera.viewfinder` / "Vision-first feedback" / "Attach photos and get critique on what you actually made."
   - Row 2 — `figure.mind.and.body` / "Coaching, not shortcuts" / "The mentor asks questions and holds you to the work."
   - Row 3 — `square.stack.3d.up` / "Every craft, one app" / "Drawing, writing, music, repair, study, and more."
4. Spacer
5. Sign in with Apple button _(unchanged)_

## New private struct added

```swift
private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String
    // HStack: blade-colored SF Symbol | bold title + muted detail | Spacer
}
```

## Design decisions

- **Colors:** blade (`#4ea3ff`) for icons; `white.opacity(0.9)` for titles; `white.opacity(0.45)` for detail text; `white.opacity(0.55)` for the description paragraph — all consistent with the existing palette.
- **Card style:** `surfaceHigh` (`#141920`) background with a very faint white border — matches the `MissingKeysCallout` pattern already in the file.
- **No spacer removed:** the top `Spacer()` was kept so the wordmark stays vertically centered on tall devices; features appear tightly below it and a second `Spacer()` pushes sign-in to the bottom.
- **No layout changes** to the sign-in area (padding, button height, error/loading states all untouched).
