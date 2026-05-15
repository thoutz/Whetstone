# Whetstone

iOS mentor app that develops human skill across crafts and processes — not one fixed topic.
Refuses to generate finished creative output on the student's behalf. See `Resources/system_prompt.txt`
for persona, vision-first photo intake, domains, and discipline details.

## Xcode setup (one-time)

1. New project → iOS → App → "Whetstone", SwiftUI, Swift, no Core Data, no tests yet
2. Delete the generated `ContentView.swift`
3. Add files: drag the `Whetstone/` source folder into the Xcode project navigator.
   Make sure "Copy items if needed" is **off** and the target membership box is checked.
4. Add `system_prompt.txt` and `advanced_system_prompt.txt` to the target: select each in the navigator →
   File Inspector → Target Membership → check Whetstone.
5. **Standalone AI path (device / TestFlight / App Store):** The app ships **`AI_BASE_URL`**, **`AI_MODEL`**, and optional **`AI_APP_TOKEN`** in **`Whetstone/Info.plist`**. At runtime the phone calls **only your HTTPS proxy** (`…/v1/chat/completions`). **`GROQ_API_KEY` lives on the VPS** (`/etc/whetstone-proxy.env`). No Groq secret is bundled in the app; nothing from Xcode scheme variables is required on a real install — those vars exist only when Xcode launches a debug build and are irrelevant once the binary leaves your Mac.

## Source layout

```
Whetstone/
  WhetstoneApp.swift          @main entry point
  AgentMode.swift             Standard vs Advanced preference + bundled prompts
  WhetstoneTheme.swift        Colors, shapes, shared design constants
  AI/
    AIClient.swift            Protocol, Message/Tool/Completion types, factory
    OpenAIChatClient.swift    OpenAI-compatible client — Groq URL or HTTPS proxy base URL
    MentorTools.swift         render_construction + render_chips + dispatcher
    AdvancedTools.swift       Advanced Mode: DNS, TCP probes, HTTP, RDAP, SSH, etc. (Citadel)
  Chat/
    ChatMessage.swift         UI-facing message model
    MentorMarkdownView.swift  Mentor prose: markdown blocks + inline styling (no SPM)
    ChatView.swift            SwiftUI chat shell; camera + photo picker, chips strip, input
  Conversation/
    Conversation.swift        Sidebar row model + time buckets
    ConversationStore.swift   All conversations, active thread, sidebar flag, agentic loop,
                              ephemeral pendingChipOffer (render_chips UI)
    SidebarView.swift         Drawer + conversation list (Claude-style grouping)
  Resources/
    system_prompt.txt         Standard mentor persona (bundled default mode)
    advanced_system_prompt.txt Advanced Mode persona + tool usage notes
```

## Key design decisions

- **Standard vs Advanced agent mode** — Default is **Standard** (mentor prompt + two tools). **Advanced** requires Supabase JWT `app_metadata.advanced_mode` and a Profile toggle; see `project-docs/advanced-agent-mode.md`. Effective chat mode always falls back to Standard without entitlement.
- **render_construction** — `dispatchToolCall` in MentorTools.swift returns `SVGPayload`;
  **ChatView** renders SVG inline via **`SVGDiagramWebView`** (WKWebView, scripts off).
- **render_chips** — Optional tool; mentor emits 2–4 `{label, value}` chips plus UI
  `"Other"`. Tapped chip sends **label** text as a normal user message. Ephemeral
  `pendingChipOffer` on ConversationStore (scoped to `conversationId`) drives the strip
  above the input bar; cleared on send, conversation switch, or "Other" (focuses field).
  When chips are emitted, **runLoop breaks** until the user replies — do not chain another
  completion in the same turn.
- **Agentic loop** — `ConversationStore.runLoop` repeats complete → dispatch tools until
  no tool calls **or** until `render_chips` payload was applied (then wait for user).
- **Standing "I'm stuck"** — Low-prominence control in the input bar sends a fixed user
  message so the mentor can branch without the student typing a paragraph.
- **Photo attach** — Camera (when available) plus Photos library picker; up to four images
  can be staged as thumbnails, resized JPEG (~1024px), then sent with optional caption.
  Image-only sends use API-only text **`(Student attached a photo with no caption.)`** so the
  model runs vision-first intake (see **`system_prompt.txt`**); the UI bubble stays image-only.
  `Message.imageJPEGData` is serialized by OpenAIChatClient as OpenAI-style multimodal `content`.
  Simulator omits the camera button when no camera exists.
- **Live camera PiP** — Tap camera to float a **draggable** preview (top-trailing, faint **green**
  outline). **Tap the preview** to capture one JPEG and send it to the mentor (same API caption as
  other image-only sends). Close via PiP × or app background. Camera denied → alert with **Open Settings**.
- **NoopClient** — if env vars are missing at launch, the app still starts and shows
  a banner. No crash.
- **Annotation overlay pattern** — the backend never returns a modified image. For
  photo annotation (Phase 2+), the model returns overlay primitives (arrows, circles,
  boxes, labels) as structured data; the client renders them as SVG above the original.
  Same pattern as the drawing critique overlay.

## Tappable response chips

The mentor may emit 2–4 tappable chips (plus automatic **Other**) when the student's
next move is a genuine small fork. Implemented via **`render_chips`** alongside prose.

**Permitted chip patterns:** orient-the-conversation; articulate-what-you-see (still
requires the student to identify — taps are faster than typing, not a shortcut around
looking); mid-conversation branch chips; the standing **I'm stuck** affordance in the UI.

**Forbidden chip patterns:** anything that skips reflection or practice gates; writing-mode
shortcuts to prose; chips as a primary navigation menu; any chip that reads like "just give
me the answer."

**UI rules:** Other always available when `include_other` is true; chips disappear once any
reply is sent or when Other clears the offer; chips never appear without mentor prose in
the same turn (model contract).

## Domains

Drawing is **one** domain among many; **`system_prompt.txt`** defines scope (repair, study, writing,
music, troubleshooting, etc.), **vision-first** behavior when students attach photos without stating
intent, generalized reflection gates, and construction-tool boundaries not tied to drawing alone.

### Drawing (Phase 1)
Gesture, contour, proportion, perspective, value. Verbal critique loop.
`render_construction` for instructional diagrams only — never representational.

### Visual photo annotation (Phase 2+)
The mentor may annotate user-uploaded photographs to teach the user to see what is
already there — engine components, circuit elements, anatomical landmarks, musical
notation, etc. Architectural rule: backend returns original image + annotation objects
(coordinates, shape, label, color). Client renders overlay as SVG. The photograph is
never modified, "enhanced," or have generated content inserted.

Permitted annotations: arrows, circles/boxes, text labels, numbered callouts, flow lines.
Forbidden: any edit to the underlying photo; speculative imagery; generative fill.

### Writing (Phase 2+)
The mentor helps writers build momentum on their own work. It may not supply prose.

Permitted: diagnostic questions, honest critique of existing drafts, structural
scaffolding (beats/functions, not story-specific events), constraints and generative
prompts, reading prescriptions, technique explanation with generic examples.

Forbidden: drafting sentences or paragraphs in the user's story, filling in dialogue,
rewriting to "show what I mean," generating story-specific plot beats, producing a
draft for the user to "react to."

The redirect for the last one: "Write the worst possible version yourself. We'll fix it
together."

### Future domains
Music (GarageBand walkthroughs, ear training, chord theory) and video.

## Backlog / next steps

- [ ] **Conversation history sidebar (sync)** — local sidebar matches Claude-style UX;
      persist history + Supabase sync still backlog.
- [ ] Confirm the loop is talking: run in simulator, send a message, check Groq response
- [ ] Photo annotation: composite SVG overlay **on** the student's image (Phase 2+)
- [ ] Supabase: Apple Sign In + user progress (see HarborMasterPro / Tavern OS for pattern)
- [ ] Curated exercises screen (5–10 drawing exercises)
- [ ] Photo capture + annotation overlay (Phase 2)
- [ ] Apple Vision on-device edge/contour detection — compressed thumbnail + features to Groq

## Hard rules (never relax these)

- No image-generation API key. No representational SVG. See original brief.
- `render_construction` and `render_chips` are the only tools **in Standard mode**. **Advanced Mode** (Supabase-gated + user toggle) adds additional on-device tools in `AdvancedTools.swift`; see `project-docs/advanced-agent-mode.md`. Adding more tools still needs deliberate review.
- Don't add "preview mode" or "just this once" affordances in the UI.
- Photo annotation: the backend never modifies the image. Overlay only, always.
- Writing: never draft prose the user could paste in. Hold the line warmly.
