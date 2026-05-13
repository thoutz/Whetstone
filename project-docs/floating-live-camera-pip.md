# Floating live camera PiP — tap to capture

**Date:** 2026-05-11 (updated same day)

## Behavior

- **Camera button** starts/stops **`CameraPiPSession`** (`LiveCameraPiP.swift`): `AVCaptureSession` + `AVCapturePhotoOutput` + preview layer.
- **`FloatingLiveCameraPiP`**: draggable top-trailing chip (~124×164 preview). **No interval timer.**
- User **taps the preview** → one still capture → JPEG via **`AttachmentEncoder`** → **`ConversationStore.send("", imageJPEGData: [data], isCameraCapture: true)`** — API caption **`(Camera photo)`**, title seed **`[Camera]`** when appropriate.
- **Visual**: faint **green** rounded stroke (**`WhetstoneTheme.pipPreviewOutline`**) around the preview; caption **“Tap preview to capture”** under the chip.
- **While capturing**: dim overlay + **`ProgressView`** on the preview; button disabled until JPEG finishes.
- **Drag**: **`DragGesture(minimumDistance: 22)`** as **`simultaneousGesture`** so short taps register as capture; longer drags reposition.
- **Permissions**: **`NSCameraUsageDescription`** / **`NSPhotoLibraryUsageDescription`** strings updated in **`project.pbxproj`** (merged Info.plist). Camera denied → alert with **Open Settings** + **OK**. **`AVCaptureDevice.authorizationStatus`** handles already-denied without hanging.

## Files

| File | Role |
|------|------|
| `Whetstone/Chat/LiveCameraPiP.swift` | Session + preview + floating UI |
| `Whetstone/Chat/ChatView.swift` | PiP overlay, handlers, camera alert |
| `Whetstone/WhetstoneTheme.swift` | `pipPreviewOutline` |
| `Whetstone/Conversation/ConversationStore.swift` | `send(..., isCameraCapture:)` |
| `Whetstone.xcodeproj/project.pbxproj` | Usage description strings |

## Build

`xcodebuild -scheme Whetstone -destination 'generic/platform=iOS' build` — succeeded.

## Notes

- PiP requires **`UIImagePickerController.isSourceTypeAvailable(.camera)`** — many **Simulators hide the camera button**; test on a **device**.
- Photo library access still flows through **`PhotosPicker`**; system prompts use **`NSPhotoLibraryUsageDescription`**.
