# Mentor scope + vision-first photo intake

**Date:** 2026-05-11

## Goal

Position Whetstone as a **general mentor** (many crafts/processes), not a drawing-only tutor. When users attach photos — especially **without text** — the model should **identify briefly**, **ask purpose and desired help**, then mentor inside that intent rather than assuming a critique workflow.

## What changed

### [`Whetstone/Resources/system_prompt.txt`](Whetstone/Resources/system_prompt.txt)

- Added **`# Scope / domains`** after **`# Your purpose`** — drawing as one domain among many.
- Added **`# When the student sends a photograph`** — staged intake before heavy critique or `render_construction`; ties into **`render_chips`** when aim forks.
- **`# What you do instead`** — neutral “ask before tell” examples; **masters** framed as domain-dependent; **practice** endings diversified beyond gesture drills.
- **`# Annotating`** — unchanged mechanics; preceded by vision-first section so annotation follows clarified intent.
- **`# The construction tool`** — **Forbidden** bullets generalized beyond “what the student is drawing.”
- **`# Reflection gates`** — generic “show what you’re working on”; sketchbook as optional; explicit skip when photo intake hasn’t clarified purpose yet.
- **`# Mission`** — emphasizes growth through effort in whatever craft/process brought them.
- **`# Tappable responses`** — first bullet for photo / intent forks.

### [`Whetstone/AI/MentorTools.swift`](Whetstone/AI/MentorTools.swift)

- **`render_construction`** tool description broadened (instructional + overlays on uploaded refs); forbid substitutes for student **work in any medium**, not drawing-only wording.

### [`Whetstone/Conversation/ConversationStore.swift`](Whetstone/Conversation/ConversationStore.swift)

- Image-only sends (camera or library): API-only **`(Student attached a photo with no caption.)`** replaces **`(Camera photo)`** / **`(Photo attached.)`** — UI still shows image-only bubbles; **`[Camera]`** / **`[Photo]`** title seeds unchanged.

### [`CLAUDE.md`](CLAUDE.md)

- Product framing + **`Domains`** intro pointing at **`system_prompt.txt`** for scope and vision-first rules.

## Architecture

No agent/tool/protocol changes beyond strings — behavior shift is **prompt + intake cue**.

## Verification

- New conversation → attach photo without caption → mentor identifies lightly and asks purpose/help before deep critique or diagrams.
