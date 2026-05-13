# Mentor diagram rendering + Groq busy errors

**Date:** 2026-05-11

## Problem

1. **`HTTP 503`** — Groq returned “model … over capacity” JSON; Configuration alert showed raw blob.
2. **`[ diagram ]`** — `render_construction` payloads were stored as `SVGPayload` but **`SVGPlaceholder`** in **`ChatView`** never drew the SVG (stub UI).

## Changes

### 1. Real SVG in chat (`SVGDiagramWebView.swift`)

- **`UIViewRepresentable`** wrapping **`WKWebView`** with **JavaScript disabled**, minimal HTML wrapper, transparent background.
- **`SVGDiagramSanitizer.embeddedFragment`** removes `<script>…</script>` blocks before embedding.
- **`MentorDiagramBlock`** (replaces **`SVGPlaceholder`**): shows **`SVGDiagramWebView`** (max width 260pt, height clamp 120–360pt), stroke, optional **`caption`** beneath (e.g. “HVAC”).
- Empty SVG → “Diagram unavailable” fallback.

### 2. Groq capacity / gateway errors (`AIClient.swift`, `OpenAIChatClient.swift`)

- **`AIError.summarizeHTTPBody`** parses Groq **`{"error":{"message":"…"}}`** for alerts.
- User-facing line for **429 / 502 / 503**: `Service busy (code): …message…`.
- **Retries**: **`OpenAIChatClient.complete`** retries same request up to **4** times with backoff **0.6s → 1.2s → 2.4s → 4.8s** on **429 / 502 / 503** only.

### 3. Mentor prompt (`system_prompt.txt`)

- Clarified that **`render_construction`** diagrams appear as a **separate inline bubble** next to prose; the student’s photo stays as uploaded above; pixel-aligned overlays on the JPEG are future work.

### 4. Xcode project

- Added **`Whetstone/Chat/SVGDiagramWebView.swift`** to target sources.

## Build

`xcodebuild -scheme Whetstone -destination 'generic/platform=iOS' build` — succeeded.

## Notes

- **503** can still occur if Groq stays overloaded after all retries — user can tap send again.
- Photo-specific “highlight” expectations: mentor SVG is **schematic** beside the thread, not drawn onto the bitmap yet (**Phase 2+** overlay architecture).
