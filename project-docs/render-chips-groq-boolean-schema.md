# render_chips Groq 400: boolean vs string parameters

Date: 2026-05-11  

## Symptom

After sending a photo, the app showed **HTTP 400** with:

`tool call validation failed: parameters for tool render_chips did not match schema: ... /allow_multi_select: expected boolean, got string ... /include_other: expected boolean, got string`

## Root cause

Groq validates assistant **tool call arguments** against the JSON Schema we send for each tool. Llama (and similar models) often serialize chip flags as **JSON strings** (`"true"` / `"false"`) instead of JSON **booleans** (`true` / `false`). The schema only allowed `boolean`, so validation failed **before** our Swift `handleRenderChips` ran.

## Fix

**File:** `Whetstone/AI/MentorTools.swift`

1. **`render_chips` schema:** For `allow_multi_select` and `include_other`, replaced plain `"type": "boolean"` with **`anyOf`**: `[boolean, string]` so either native booleans or string forms pass Groq validation.

2. **Parsing:** Added `mentorBool(from:default:)` and use it when reading those keys so we still normalize strings, real booleans, and small integers consistently.

## Verification

- Build: `xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build`.
- Manual: Send a message that triggers `render_chips` (e.g. photo + mentor fork); confirm no Configuration alert and chips appear when intended.

## Note

If Groq ever rejects `anyOf` in tool schemas, alternative is `type: string` only + coercion (trade-off: real JSON booleans might fail validation).
