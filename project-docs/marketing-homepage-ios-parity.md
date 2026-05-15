# Marketing homepage — iOS visual parity (BladeEdge + theme)

## What changed

Redesigned [server/whetstone-website/index.html](server/whetstone-website/index.html) so the public landing page feels closer to the in-app chat UI instead of the prior serif/gold editorial look.

### iOS references

- **Palette** — [Whetstone/WhetstoneTheme.swift](../Whetstone/WhetstoneTheme.swift): `obsidian`, `blade`, `ember`, `surface`, `surfaceHigh`, chamfer dimension.
- **Mentor vertical rail** — [Whetstone/Chat/ChatView.swift](../Whetstone/Chat/ChatView.swift) `BladeEdge` (approx. lines 815–836): gradient bar `ember` → `blade` → `blade.opacity(0.15)` top-to-bottom on a **2px** wide strip, plus **ember** spark `Circle()` **7px** with glow; rail width aligns with `bladeEdgeWidth + sparkDotSize`.
- **User bubble chamfer** — `UserMessageView` + `ChamferedTopRight` (~14px bevel top-trailing); approximated on the web with `clip-path` + `surfaceHigh` fill and blade-tint border.
- **HUD wordmark** — Chat header style: monospaced `WHETSTONE` with blade-like coloring (web uses IBM Plex Mono; app uses system monospaced).

### Web implementation notes

- **`.blade-rail`** — CSS `linear-gradient` on a 2px bar; separate `.spark` absolutely positioned to mirror Swift `ZStack(alignment: .top)`.
- **Preview thread** — Fictional user line + mentor block + chip row styled like in-app chips (capsule, `surfaceHigh`, blade stroke).
- **Feature cards** — Thin vertical gradient strip (ember → blade) as a lighter echo of the full mentor rail.
- **Fonts** — Dropped Instrument Serif; **Source Sans 3** for body, **IBM Plex Mono** for HUD labels / chips / footer (no new build steps — Google Fonts link only).

### Deploy

Sync `server/whetstone-website/index.html` to the VPS web root (e.g. `/var/www/whetstone-website/`) as in [website-admin-dashboard.md](website-admin-dashboard.md).

## Copy pass (homepage tone)

Landing copy has been iterated for a lighter, conversational voice: **`hone`** in the hero headline, wink about matching a sharpening stone, and a clearer **WHAT’S GOING ON** strip for photos / chips / breadth (titles like **Pic first, sermon later**).
