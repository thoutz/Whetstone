# Camera and photo library attachments

**Date:** 2026-05-11

## Why

The input bar previously showed non-functional `CODE` / `WEB` / `ATTACH` labels. Students need visible **camera** and **library** affordances to share photos with the mentor (engines, sketches, etc.).

## Behavior

- **Camera** (`camera.fill`): Shown only when `UIImagePickerController.isSourceTypeAvailable(.camera)` is true (hidden on most simulators). Opens full-screen `UIImagePickerController`.
- **Library** (`photo.on.rectangle`): `PhotosPicker` (PhotosUI), multi-select up to four items per invocation; total staged attachments capped at four.
- **Staging**: Selected images appear as a horizontal strip with remove (`x`) controls; **Strike** sends optional draft text plus all staged JPEGs, then clears staging.
- **Send without text**: Photo-only sends use API line `(Photo attached.)` while the bubble can show images only (empty visible caption).

## Implementation notes

| Area | Detail |
|------|--------|
| `ChatMessage` | `attachedImages: [Data]` for thumbnails in transcript |
| `Message` (wire) | `imageJPEGData: [Data]?` on user turns |
| `OpenAIChatClient` | User + images → `content` array with `text` + `image_url` data URIs |
| `ConversationStore.send(_:imageJPEGData:)` | Appends UI + API messages; title `[Photo]` when text empty |
| Info.plist | Generated keys: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` |

Images are recompressed with `UIGraphicsImageRenderer` max dimension 1024 and JPEG quality ~0.72.

## Build

`xcodebuild -scheme Whetstone -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeded after these changes.
