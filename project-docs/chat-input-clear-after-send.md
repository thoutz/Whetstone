# Chat input not clearing after send

**Date:** 2026-05-11

## Symptom

After sending text from the multiline composer, the message appeared in the thread and Groq replied, but the same text remained in the **TextField**.

## Cause

`TextField(..., axis: .vertical)` maps to a multi-line text path where UIKit can **write the current content back into the SwiftUI binding** after the `.onSubmit` / keyboard send action runs. `send()` cleared `draft` synchronously, then the field restored it.

## Fix

In [`ChatView.swift`](Whetstone/Chat/ChatView.swift) `send()`: keep an immediate `draft = ""`, then **`DispatchQueue.main.async { draft = "" }`** after `store.send(...)` so the second clear runs on the next turn, after the stray re-bind.

## Files

- [`Whetstone/Chat/ChatView.swift`](Whetstone/Chat/ChatView.swift)
