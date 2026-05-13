# Sidebar long-press context menu (conversations)

**Date:** 2026-05-12  
**Scope:** Tap-and-hold (context menu) on sidebar conversation rows: **Pin**, **Rename**, **Add to project**, **Delete**; pinned + per-project sections; device-local `Project` model; sync fields for pin / `project_id` on conversation PATCH.

## Files added

| File | Purpose |
|------|---------|
| [`Whetstone/Conversation/Project.swift`](../Whetstone/Conversation/Project.swift) | `Project` model: `id`, `name`, `createdAt` |

## Files modified

| File | Changes |
|------|---------|
| [`Whetstone/Conversation/Conversation.swift`](../Whetstone/Conversation/Conversation.swift) | `isPinned`, `projectId` |
| [`Whetstone/Conversation/ConversationStore.swift`](../Whetstone/Conversation/ConversationStore.swift) | `@Published projects`; `setPinned`, `renameConversation`, `assignToProject`, `createProject`; `sidebarSections` + private `timeGroupedBuckets`; clear `projects` on logout |
| [`Whetstone/Conversation/SidebarView.swift`](../Whetstone/Conversation/SidebarView.swift) | `ForEach(store.sidebarSections)`; `.contextMenu` on rows; pin glyph; rename sheet (form + nav buttons); `ProjectPickerSheet`; `.id` suffix so duplicate rows (same thread in multiple sections) are distinct |
| [`Whetstone/Conversation/ConversationPersistence.swift`](../Whetstone/Conversation/ConversationPersistence.swift) | Decode optional `is_pinned`, `project_id` on detail; PATCH includes `is_pinned` + `project_id` (UUID string or JSON null) |
| [`Whetstone.xcodeproj/project.pbxproj`](../Whetstone.xcodeproj/project.pbxproj) | Added `Project.swift` to Conversation group and Sources |

## Behavior

- **Pin:** Sets `isPinned`; thread appears under **PINNED** first, and still appears in its time bucket and any project section.
- **Rename:** Medium sheet with text field; title capped at 256 chars in store.
- **Add to project:** Sheet lists **None**, existing projects (checkmark on current), toolbar **New Project** + alert with name field. `Project` list is **in-memory only** (cleared on logout); not synced to the VPS until a projects API exists. Conversation `project_id` **is** sent on PATCH when signed in (server may ignore until schema supports it).
- **Delete:** Same as before; swipe-to-delete kept.

## Build verification

```bash
xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Notes

- Context menu icon for *Add to project* uses SF Symbol `tray.and.arrow.down.fill` (folder-style tray).
- Backend must accept or ignore extra PATCH keys `is_pinned` / `project_id`; if strict validation rejects unknown keys, proxy/DB migration will be required.
