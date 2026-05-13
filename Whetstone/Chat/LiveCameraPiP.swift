import AVFoundation
import SwiftUI
import UIKit

// MARK: - Session (preview feed + tap / programmatic capture)

@MainActor
final class CameraPiPSession: ObservableObject {

    @Published private(set) var isRunning = false
    @Published var authorizationDenied = false

    /// JPEG payload delivered after each successful capture.
    var onPhotoCaptured: ((Data) -> Void)?

    let captureSession = AVCaptureSession()

    /// Weak link to the live preview host for instant snapshot-to-chat (preview layer).
    fileprivate weak var previewHostForSnapshot: PreviewHostView?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "whetstone.camera.pip.session")

    private var isCapturingPhoto = false
    private var photoDelegateRetain: PiPPhotoDelegate?

    func start() {
        guard !isRunning else { return }
        authorizationDenied = false

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            authorizationDenied = true
            return
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard granted else {
                    await MainActor.run { authorizationDenied = true }
                    return
                }
                await MainActor.run { beginRunningSession() }
            }
        case .authorized:
            beginRunningSession()
        @unknown default:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard granted else {
                    await MainActor.run { authorizationDenied = true }
                    return
                }
                await MainActor.run { beginRunningSession() }
            }
        }
    }

    private func beginRunningSession() {
        configureSessionIfNeeded()

        sessionQueue.async { [captureSession] in
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }

        isRunning = true
    }

    func stop() {
        isCapturingPhoto = false
        photoDelegateRetain = nil
        previewHostForSnapshot = nil

        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }

        isRunning = false
    }

    /// Renders the live preview layer into an image. **Often all-black on device**: preview pixels are not
    /// reliably rasterized through `CALayer.render`; callers must validate before trusting pixels.
    private func snapshotPreviewUIImage() -> UIImage? {
        guard let host = previewHostForSnapshot else { return nil }
        host.layoutIfNeeded()
        let bounds = host.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { ctx in
            host.previewLayer.render(in: ctx.cgContext)
        }
    }

    /// Prefers an instant preview-layer snapshot when it carries real pixels; otherwise full-resolution photo.
    func capturePhoto() {
        guard isRunning else { return }

        if let snapshot = snapshotPreviewUIImage(),
           snapshot.whetstonePreviewSnapshotLooksPopulated,
           let jpeg = AttachmentEncoder.jpeg(from: snapshot) {
            onPhotoCaptured?(jpeg)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        guard !isCapturingPhoto else { return }
        isCapturingPhoto = true

        let delegate = PiPPhotoDelegate { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isCapturingPhoto = false
                self.photoDelegateRetain = nil

                guard case .success(let data) = result,
                      let ui = UIImage(data: data),
                      let jpeg = AttachmentEncoder.jpeg(from: ui)
                else { return }

                self.onPhotoCaptured?(jpeg)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        photoDelegateRetain = delegate

        sessionQueue.async { [photoOutput] in
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func configureSessionIfNeeded() {
        guard captureSession.inputs.isEmpty else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
    }
}

// MARK: - Photo delegate (must stay alive until capture completes)

private final class PiPPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let onFinish: (Result<Data, Error>) -> Void

    init(onFinish: @escaping (Result<Data, Error>) -> Void) {
        self.onFinish = onFinish
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            onFinish(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            onFinish(.failure(NSError(domain: "PiP", code: -1)))
            return
        }
        onFinish(.success(data))
    }
}

// MARK: - Preview layer host

private final class PreviewHostView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct CameraPiPPreview: UIViewRepresentable {
    @ObservedObject var pipSession: CameraPiPSession

    func makeUIView(context: Context) -> PreviewHostView {
        let v = PreviewHostView()
        v.previewLayer.session = pipSession.captureSession
        v.previewLayer.videoGravity = .resizeAspectFill
        pipSession.previewHostForSnapshot = v
        return v
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.previewLayer.session = pipSession.captureSession
        pipSession.previewHostForSnapshot = uiView
    }
}

// MARK: - Floating PiP UI

struct FloatingLiveCameraPiP: View {
    @ObservedObject var session: CameraPiPSession
    @Binding var dragOffset: CGSize

    @GestureState private var dragGesture: CGSize = .zero

    var body: some View {
        let combined = CGSize(
            width: dragOffset.width + dragGesture.width,
            height: dragOffset.height + dragGesture.height
        )

        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button {
                    session.capturePhoto()
                } label: {
                    CameraPiPPreview(pipSession: session)
                        .frame(width: 124, height: 164)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(WhetstoneTheme.pipPreviewOutline, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    session.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white.opacity(0.92), Color.black.opacity(0.5))
                        .font(.system(size: 27))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close live camera")
                .offset(x: 4, y: -4)
            }

            Text("Tap preview to capture")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(WhetstoneTheme.pipPreviewOutline.opacity(0.92))
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .offset(combined)
        .simultaneousGesture(
            DragGesture(minimumDistance: 22)
                .updating($dragGesture) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    dragOffset.width += value.translation.width
                    dragOffset.height += value.translation.height
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live camera preview. Tap to capture and send to your mentor. Drag to reposition.")
    }
}

// MARK: - Preview snapshot sanity check

private extension UIImage {
    /// `AVCaptureVideoPreviewLayer.render(in:)` frequently yields an all-black bitmap on device; reject those so we fall back to `AVCapturePhotoOutput`.
    var whetstonePreviewSnapshotLooksPopulated: Bool {
        guard let maxChannel = whetstoneMaxRGBSample(side: 48) else { return false }
        return maxChannel >= 6.0 / 255.0
    }

    func whetstoneMaxRGBSample(side: Int) -> CGFloat? {
        guard let cgImage = cgImage else { return nil }
        let w = side
        let h = side
        let bytesPerRow = w * 4
        guard let context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = context.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var maxChannel: UInt8 = 0
        let pixelCount = w * h
        for i in 0..<pixelCount {
            let o = i * 4
            maxChannel = max(maxChannel, ptr[o], ptr[o + 1], ptr[o + 2])
        }
        return CGFloat(maxChannel) / 255.0
    }
}
