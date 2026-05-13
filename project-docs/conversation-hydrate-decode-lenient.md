# Conversation hydrate decode (“data … is missing”)

## Symptom

After a successful login / JWT fix, reopening the app showed:

> Could not load your conversations: The data couldn't be read because it is missing.

That string is Swift **`DecodingError`** (typically **`keyNotFound`**) while decoding the conversation API JSON — not auth or Postgres connectivity.

## Likely causes

1. **ISO-8601 timestamps** from Postgres / Node (`toISOString()`, microsecond precision) — `JSONDecoder.DateDecodingStrategy.iso8601` does **not** accept all fractional-second variants.
2. **Strict nested DTOs** — e.g. `PersistedMetaDTO` / `PersistedSvgDTO` / tool `function.arguments` requiring keys that are absent or shaped differently after round-trip.
3. **Missing arrays** — defensive `decodeIfPresent … ?? []` for `api_history` / `messages` if the API ever omits them.

## Changes ([`ConversationPersistence.swift`](../Whetstone/Conversation/ConversationPersistence.swift))

- **`ConversationISO8601`** — custom `dateDecodingStrategy` trying ISO8601 **with** fractional seconds, then without, then common Postgres-style fallbacks.
- **`ConversationListEnvelope`** — `conversations` defaults to `[]` if absent.
- **`WireConversationDetailRecord`** — explicit decode; `apiHistory` / `messages` default to `[]`.
- **`PersistedMetaDTO`**, **`PersistedSvgDTO`** — lenient `init(from:)` with defaults for missing keys.
- **`WireNestedToolCallDTO` / `WireFn`** — tolerate missing `id`/`type`; **`arguments`** may be non-string → default **`"{}"`**.
- **`decodeUIMessageRow`** — treat empty SVG string as no diagram.

## Console noise

Logs such as `fopen failed for data file`, pasteboard, `TUIKeyboardCandidateMultiplexer`, `Reporter disconnected` are common iOS simulator / keyboard churn and are unrelated to conversation JSON decoding.
