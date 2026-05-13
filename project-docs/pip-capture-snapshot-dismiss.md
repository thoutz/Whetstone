# PiP capture UX: preview snapshot, dismiss, keyboard

Date: 2026-05-11  

## Summary

Implemented the PiP plan: fixed layout so the green stroke no longer expands with unconstrained views, enlarged the close control, dismiss PiP after a successful capture send, prefer instant JPEG from the live preview layer with `AVCapturePhotoOutput` fallback, and set the composer keyboard to letters-first ASCII.

## Files changed

### `Whetstone/Chat/LiveCameraPiP.swift`

- **Stroke bug:** Removed the capture-state `ZStack` overlay (`ProgressView` + dimming). Unbounded `ProgressView` could inflate the hit area so the green `.stroke` overlay traced a huge rectangle. The preview is now a single fixed **124×164** `CameraPiPPreview` with clip + stroke only on that region.
- **Close button:** `xmark.circle.fill` at **27pt** inside an explicit **44×44** frame with `contentShape(Rectangle())` for HIG-aligned targeting; slight offset so it sits cleanly on the corner.
- **Instant capture:** `CameraPiPSession` holds `fileprivate weak var previewHostForSnapshot`. `CameraPiPPreview` (`UIViewRepresentable`) assigns it in `makeUIView` / `updateUIView`.
- **`snapshotPreviewUIImage()`:** `layoutIfNeeded()`, guard non-trivial `bounds`, `UIGraphicsImageRenderer` + **`previewLayer.render(in:)`** → `UIImage`, then **`AttachmentEncoder.jpeg(from:)`** when validated.
- **Population gate:** **`whetstonePreviewSnapshotLooksPopulated`** downsamples and checks max RGB (`≥ 6/255`). On device, **`AVCaptureVideoPreviewLayer`** often produces **solid black** bitmaps via `render(in:)` while the live preview looks normal—we reject those and use **`AVCapturePhotoOutput`** instead of uploading garbage.
- **`capturePhoto()`:** Snapshot fast-path only when pixels look non-black; otherwise full **`AVCapturePhotoOutput`** (`PiPPhotoDelegate`). One delivery per tap.
- **`stop()`:** Clears `previewHostForSnapshot`, retains existing session teardown.
- Removed **`@Published isCapturing`** and UI `.disabled` during capture (no overlay).

### `Whetstone/Chat/ChatView.swift`

- **`configurePiPSessionIfNeeded`:** After `store.send(..., isCameraCapture: true)`, calls **`pipSession.stop()`** so PiP closes without tapping X.
- **Composer:** `.keyboardType(.default)` → **`.keyboardType(.asciiCapable)`** so the keyboard tends to open on the letters plane instead of restoring numbers/symbols.

## Build / verification

- `xcodebuild -scheme Whetstone -destination 'generic/platform=iOS Simulator' build` — **succeeded**.

## Manual QA notes

- On **physical device**, expect the **photo fallback** path most of the time (PiP stays open briefly until `AVCapturePhotoOutput` completes). Simulators may still take the snapshot fast-path occasionally.
- Non-Latin locales: if `.asciiCapable` causes issues, consider locale-aware keyboard type later.

## Troubleshooting: black image in chat (2026-05-11)

**Symptom:** PiP dismisses and a user bubble appears, but the JPEG is solid black.

**Cause:** `CALayer.render(in:)` / `UIGraphicsImageRenderer` does not reliably capture **`AVCaptureVideoPreviewLayer`** contents; GPU-backed camera preview can yield an empty bitmap.

**Fix shipped:** Treat “max RGB across a downsampled snapshot” as a gate; all-black → skip fast path and use **`AVCapturePhotoOutput`** for a real still.

**Future (optional):** For instant + reliable pixels without this heuristic, add **`AVCaptureVideoDataOutput`** and grab the latest `CMSampleBuffer` (more moving parts than still capture).
