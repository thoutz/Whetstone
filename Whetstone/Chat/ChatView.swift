import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {

    @EnvironmentObject var store: ConversationStore
    @EnvironmentObject private var auth: AuthManager

    @State private var showProfile = false

    /// Dim yellow for Profile affordance (matches plan).
    private static let profileLabelColor = Color(hex: "c8a84b").opacity(0.5)
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var pipSession = CameraPiPSession()
    @State private var pipDragOffset: CGSize = .zero

    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @State private var stagedJPEGs: [Data] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    /// Bumps when chat activity might leave UIKit holding the wrong keyboard plane for the composer.
    @State private var composerKeyboardHookTick = 0

    @State private var scrollViewportBottomGlobalY: CGFloat = 0
    @State private var chatTranscriptBottomGlobalY: CGFloat = 0
    @State private var showJumpToLatest = false

    /// Portion of the keyboard overlapping the key window (pt). Used for extra transcript bottom inset while typing.
    @State private var keyboardBottomInset: CGFloat = 0
    /// Bumped when the keyboard frame changes while composing; triggers scroll-to-bottom inside `ScrollViewReader`.
    @State private var transcriptScrollToBottomTick: Int = 0

    /// Cleared when switching threads so the near-limit banner can show again if needed.
    @State private var contextLimitBannerDismissed = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WhetstoneTheme.obsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                hud
                messageList
                chipStripSection
                contextLimitBannerSection
                inputBar
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.88),
                       value: store.visibleChipPayload != nil || store.shouldOfferContextLimitBanner)

            if pipSession.isRunning {
                FloatingLiveCameraPiP(session: pipSession, dragOffset: $pipDragOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 340)
                    .padding(.trailing, 8)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: pipSession.isRunning)
        .preferredColorScheme(.dark)
        .alert("Configuration", isPresented: .constant(store.errorBanner != nil)) {
            Button("OK") { store.errorBanner = nil }
        } message: {
            Text(store.errorBanner ?? "")
        }
        .onAppear { configurePiPSessionIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pipSession.stop()
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environmentObject(auth)
        }
        .alert("Camera access", isPresented: Binding(
            get: { pipSession.authorizationDenied },
            set: { pipSession.authorizationDenied = $0 }
        )) {
            Button("Open Settings") {
                pipSession.authorizationDenied = false
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {
                pipSession.authorizationDenied = false
            }
        } message: {
            Text("Allow camera access so you can open the live preview and tap it to capture a photo for your mentor. You can change this anytime in Settings.")
        }
        .onChange(of: store.isThinking) { _, thinking in
            if !thinking {
                composerKeyboardHookTick &+= 1
            }
        }
        .onChange(of: store.activeId) { _, _ in
            contextLimitBannerDismissed = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let overlap = Self.keyboardOverlap(from: note)
            keyboardBottomInset = overlap
            if inputFocused, overlap > 1 {
                transcriptScrollToBottomTick &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardBottomInset = 0
        }
    }

    /// Extra scrollable space under the transcript while the composer is focused and the keyboard is visible.
    private var transcriptKeyboardBottomPadding: CGFloat {
        guard inputFocused, keyboardBottomInset > 1 else { return 0 }
        return keyboardBottomInset
    }

    private func configurePiPSessionIfNeeded() {
        pipSession.onPhotoCaptured = { data in
            store.send("", imageJPEGData: [data], isCameraCapture: true)
            pipSession.stop()
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard
            let info = notification.userInfo,
            let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = keyWindow()
        else { return 0 }
        let kbFrame = window.convert(endFrame, from: nil)
        return kbFrame.intersection(window.bounds).height
    }

    private func scheduleTranscriptScrollToBottom(proxy: ScrollViewProxy) {
        func scroll() {
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        DispatchQueue.main.async(execute: scroll)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: scroll)
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Sidebar toggle
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        store.sidebarOpen.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                }

                Text("WHETSTONE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.9))

                Spacer()

                if store.isThinking {
                    HoningDots()
                }

                Text(store.contextPercentString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            BladeGauge(fillFraction: store.contextFraction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(WhetstoneTheme.obsidian)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WhetstoneTheme.blade.opacity(0.12))
                .frame(height: 1)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(store.messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ChatTranscriptBottomKey.self,
                                        value: geo.frame(in: .global).maxY
                                    )
                                }
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20 + transcriptKeyboardBottomPadding)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ChatScrollViewportBottomKey.self,
                            value: geo.frame(in: .global).maxY
                        )
                    }
                )
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(ChatScrollViewportBottomKey.self) { y in
                    scrollViewportBottomGlobalY = y
                    refreshJumpToLatestVisibility()
                }
                .onPreferenceChange(ChatTranscriptBottomKey.self) { y in
                    chatTranscriptBottomGlobalY = y
                    refreshJumpToLatestVisibility()
                }
                .onChange(of: transcriptScrollToBottomTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: inputFocused) { _, focused in
                    if focused {
                        composerKeyboardHookTick &+= 1
                        scheduleTranscriptScrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: store.messages.count) { _, _ in
                    showJumpToLatest = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: store.activeId) { _, _ in
                    showJumpToLatest = false
                    proxy.scrollTo("bottom", anchor: .bottom)
                }

                if showJumpToLatest && !store.messages.isEmpty {
                    JumpToLatestButton {
                        showJumpToLatest = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
    }

    private func refreshJumpToLatestVisibility() {
        let viewport = scrollViewportBottomGlobalY
        let contentBottom = chatTranscriptBottomGlobalY
        guard viewport > 1, contentBottom > 1 else {
            showJumpToLatest = false
            return
        }
        let tolerance: CGFloat = 20
        showJumpToLatest = contentBottom > viewport + tolerance
    }

    // MARK: - Tappable chips

    @ViewBuilder
    private var chipStripSection: some View {
        if let payload = store.visibleChipPayload {
            ChipsStrip(payload: payload) {
                store.dismissChipOfferForOther()
                inputFocused = true
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var contextLimitBannerSection: some View {
        Group {
            if store.shouldOfferContextLimitBanner && !contextLimitBannerDismissed {
                ContextLimitBanner(
                    onNewChat: {
                        guard !store.isThinking else { return }
                        store.newConversation()
                    },
                    onDismiss: { contextLimitBannerDismissed = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(WhetstoneTheme.blade.opacity(0.12))
                .frame(height: 1)

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    if cameraAvailable {
                        Button {
                            if pipSession.isRunning {
                                pipSession.stop()
                            } else {
                                configurePiPSessionIfNeeded()
                                pipSession.start()
                            }
                        } label: {
                            Image(systemName: pipSession.isRunning ? "dot.radiowaves.left.and.right" : "camera.fill")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(
                                    pipSession.isRunning
                                        ? WhetstoneTheme.ember
                                        : Color.white.opacity(0.42)
                                )
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pipSession.isRunning ? "Stop live camera" : "Open live camera preview")
                    }

                    PhotosPicker(
                        selection: $photoPickerItems,
                        maxSelectionCount: AttachmentLimits.maxImages,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.white.opacity(stagedJPEGs.count >= AttachmentLimits.maxImages ? 0.15 : 0.42))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(store.isThinking || stagedJPEGs.count >= AttachmentLimits.maxImages)
                    .accessibilityLabel("Choose photo from library")

                    Spacer(minLength: 8)

                    Button {
                        guard !store.isThinking else { return }
                        showProfile = true
                    } label: {
                        Text("Profile")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(Self.profileLabelColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isThinking)
                }

                if !stagedJPEGs.isEmpty {
                    stagedAttachmentsStrip
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("", text: $draft, axis: .vertical)
                        .focused($inputFocused)
                        .lineLimit(1...5)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .tint(WhetstoneTheme.ember)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .placeholder(when: draft.isEmpty) {
                            Text("›  ready to strike")
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.2))
                        }
                        .background(alignment: .leading) {
                            ComposerAsciiKeyboardHook(tick: composerKeyboardHookTick, isFocused: inputFocused)
                                .frame(width: 4, height: 4)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .id("whetstoneChatComposerField")

                    StrikeButton(active: canSend, action: send)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(WhetstoneTheme.obsidian)
            .onChange(of: photoPickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(from: items) }
            }
        }
    }

    private var stagedAttachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(stagedJPEGs.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        if let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(WhetstoneTheme.blade.opacity(0.25), lineWidth: 1)
                                )
                        }
                        Button {
                            stagedJPEGs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.55))
                                .font(.system(size: 18))
                        }
                        .offset(x: 7, y: -7)
                        .disabled(store.isThinking)
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || !stagedJPEGs.isEmpty) && !store.isThinking
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !stagedJPEGs.isEmpty), !store.isThinking else { return }
        let bundle = stagedJPEGs
        draft = ""
        stagedJPEGs = []
        store.send(text, imageJPEGData: bundle)
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        let budget = AttachmentLimits.maxImages - stagedJPEGs.count
        guard budget > 0 else {
            await MainActor.run { photoPickerItems = [] }
            return
        }
        var datas: [Data] = []
        for item in items.prefix(budget) {
            if let raw = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: raw),
               let jpeg = AttachmentEncoder.jpeg(from: ui) {
                datas.append(jpeg)
            }
        }
        await MainActor.run {
            stagedJPEGs.append(contentsOf: datas)
            photoPickerItems = []
        }
    }

}

/// Multiline SwiftUI `TextField` bridges to `UITextView`. iOS can restore the numbers/symbols keyboard plane after
/// chat updates even when `.keyboardType(.asciiCapable)` is declared; re-apply on the real view when the hook ticks.
/// Avoid `reloadInputViews()` here — it rebuilds the keyboard and can leave it on the symbols plane.
private struct ComposerAsciiKeyboardHook: UIViewRepresentable {
    var tick: Int
    var isFocused: Bool

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        _ = tick
        guard isFocused else { return }
        DispatchQueue.main.async {
            guard let target = Self.findNearbyTextInput(from: uiView) else { return }
            if let tv = target as? UITextView {
                tv.keyboardType = .asciiCapable
            } else if let tf = target as? UITextField {
                tf.keyboardType = .asciiCapable
            }
        }
    }

    private static func findNearbyTextInput(from anchor: UIView) -> UIView? {
        var node: UIView? = anchor
        for _ in 0..<32 {
            guard let current = node else { break }
            if let found = breadthFirstTextInput(in: current) { return found }
            node = current.superview
        }
        return nil
    }

    private static func breadthFirstTextInput(in root: UIView) -> UIView? {
        var queue: [UIView] = [root]
        var index = 0
        while index < queue.count {
            let v = queue[index]
            index += 1
            if v is UITextView || v is UITextField { return v }
            queue.append(contentsOf: v.subviews)
        }
        return nil
    }
}

// MARK: - Chat scroll geometry (jump to latest)

private struct ChatScrollViewportBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatTranscriptBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Photo attachments (library compression helpers)

private enum AttachmentLimits {
    static let maxImages = 4
}

enum AttachmentEncoder {
    static func jpeg(from image: UIImage) -> Data? {
        let resized = image.whetstoneResized(maxDimension: 1024)
        return resized.jpegData(compressionQuality: 0.72)
    }
}

extension UIImage {
    func whetstoneResized(maxDimension: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let scale = min(maxDimension / w, maxDimension / h, 1)
        guard scale < 1 else { return self }
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Chips strip (render_chips)

private struct ChipsStrip: View {
    @EnvironmentObject var store: ConversationStore
    let payload: ChipsPayload
    let onOtherTap: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(payload.chips.enumerated()), id: \.offset) { _, chip in
                    chipPill(chip.label, subdued: false) {
                        store.send(chip.label)
                    }
                }
                if payload.includeOther {
                    chipPill("Other", subdued: true, action: onOtherTap)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(WhetstoneTheme.obsidian)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WhetstoneTheme.blade.opacity(0.12))
                .frame(height: 1)
        }
    }

    private func chipPill(_ title: String, subdued: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(subdued ? 0.55 : 0.92))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(WhetstoneTheme.surfaceHigh))
                .overlay(
                    Capsule()
                        .stroke(WhetstoneTheme.blade.opacity(subdued ? 0.28 : 0.42), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.isThinking)
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:    UserMessageView(message: message)
        case .mentor, .tool: MentorMessageView(message: message)
        }
    }
}

// MARK: - User message

private struct UserMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachedImages.isEmpty {
                    ForEach(Array(message.attachedImages.enumerated()), id: \.offset) { _, data in
                        if let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(WhetstoneTheme.blade.opacity(0.22), lineWidth: 1)
                                )
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(ChamferedTopRight().fill(WhetstoneTheme.surfaceHigh))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Mentor message

private struct MentorMessageView: View {
    let message: ChatMessage

    @State private var copyFeedbackTick = 0

    private var resolvedCopyPayload: (string: String, menuTitle: String)? {
        Self.copyPayload(for: message)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BladeEdge()
                .frame(width: WhetstoneTheme.bladeEdgeWidth + WhetstoneTheme.sparkDotSize)

            HStack(alignment: .top, spacing: 8) {
                mentorContentColumn
                    .contextMenu {
                        if let payload = resolvedCopyPayload {
                            Button(payload.menuTitle) {
                                Self.copyToPasteboard(payload.string)
                                copyFeedbackTick &+= 1
                            }
                        }
                    }

                if resolvedCopyPayload != nil {
                    Button {
                        guard let payload = resolvedCopyPayload else { return }
                        Self.copyToPasteboard(payload.string)
                        copyFeedbackTick &+= 1
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .buttonStyle(MentorCopyAffordanceStyle())
                    .accessibilityLabel(Self.copyAccessibilityLabel(for: message))
                    .accessibilityHint(message.text.isEmpty ? "Copies the diagram caption to the clipboard." : "Copies the mentor reply to the clipboard.")
                }
            }

            Spacer(minLength: 24)
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTick)
    }

    @ViewBuilder
    private var mentorContentColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                MentorMarkdownView(text: message.text)
            }
            if let svg = message.svgPayload {
                MentorDiagramBlock(payload: svg)
            }
            if let meta = message.meta {
                HonedRow(meta: meta)
            }
            if let payload = resolvedCopyPayload {
                HStack {
                    Spacer(minLength: 0)
                    ShareLink(item: payload.string) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .buttonStyle(MentorCopyAffordanceStyle())
                    .accessibilityLabel(Self.shareAccessibilityLabel(for: message))
                    .accessibilityHint(Self.shareAccessibilityHint(for: message))
                }
            }
        }
    }

    /// Clipboard string and context-menu title. Response text takes precedence; diagram caption only when prose is empty.
    private static func copyPayload(for message: ChatMessage) -> (string: String, menuTitle: String)? {
        if !message.text.isEmpty {
            return (message.text, "Copy response")
        }
        if let raw = message.svgPayload?.caption,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (raw, "Copy caption")
        }
        return nil
    }

    private static func copyAccessibilityLabel(for message: ChatMessage) -> String {
        if !message.text.isEmpty { return "Copy response" }
        return "Copy caption"
    }

    private static func shareAccessibilityLabel(for message: ChatMessage) -> String {
        if !message.text.isEmpty { return "Share response" }
        return "Share caption"
    }

    private static func shareAccessibilityHint(for message: ChatMessage) -> String {
        if !message.text.isEmpty {
            return "Opens the share sheet with the mentor reply."
        }
        return "Opens the share sheet with the diagram caption."
    }

    private static func copyToPasteboard(_ string: String) {
        UIPasteboard.general.string = string
    }
}

private struct MentorCopyAffordanceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? WhetstoneTheme.blade : Color.white.opacity(0.35))
    }
}

// MARK: - Blade edge

private struct BladeEdge: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: WhetstoneTheme.ember, location: 0),
                    .init(color: WhetstoneTheme.blade, location: 0.3),
                    .init(color: WhetstoneTheme.blade.opacity(0.15), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: WhetstoneTheme.bladeEdgeWidth)
            .frame(maxHeight: .infinity)
            .padding(.leading, (WhetstoneTheme.sparkDotSize - WhetstoneTheme.bladeEdgeWidth) / 2)

            Circle()
                .fill(WhetstoneTheme.ember)
                .frame(width: WhetstoneTheme.sparkDotSize, height: WhetstoneTheme.sparkDotSize)
                .shadow(color: WhetstoneTheme.ember.opacity(0.7), radius: 4)
        }
    }
}

// MARK: - HONED meta row

private struct HonedRow: View {
    let meta: ChatMessage.ResponseMeta

    private var label: String {
        let t = meta.durationSeconds < 1
            ? String(format: "%.0fms", meta.durationSeconds * 1000)
            : String(format: "%.1fs", meta.durationSeconds)
        let k = meta.completionTokens >= 1000
            ? String(format: "%.1fk", Double(meta.completionTokens) / 1000)
            : "\(meta.completionTokens)"
        return "/// HONED · \(t) · \(k) tok"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(WhetstoneTheme.ember.opacity(0.45))
            .tracking(0.5)
    }
}

// MARK: - Jump to latest messages

private struct JumpToLatestButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(WhetstoneTheme.surfaceHigh)
                    .frame(width: 44, height: 44)
                    .shadow(color: WhetstoneTheme.blade.opacity(0.35), radius: 6, x: 0, y: 2)

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WhetstoneTheme.blade)
            }
            .overlay(
                Circle()
                    .stroke(WhetstoneTheme.blade.opacity(0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to latest messages")
    }
}

// MARK: - STRIKE button

private struct StrikeButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? WhetstoneTheme.blade : Color.white.opacity(0.07))
                    .frame(width: 44, height: 36)
                    .shadow(color: active ? WhetstoneTheme.blade.opacity(0.4) : .clear,
                            radius: 6, x: 0, y: 2)

                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(active ? WhetstoneTheme.obsidian : Color.white.opacity(0.2))
                    .rotationEffect(.degrees(-12))
            }
        }
        .disabled(!active)
        .animation(.easeInOut(duration: 0.15), value: active)
    }
}

// MARK: - Context limit banner

private struct ContextLimitBanner: View {
    let onNewChat: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WhetstoneTheme.ember.opacity(0.9))

            Text("Conversation is nearing its limit")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("New chat", action: onNewChat)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(WhetstoneTheme.ember)
                .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss limit warning")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WhetstoneTheme.surfaceHigh)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WhetstoneTheme.ember.opacity(0.22))
                .frame(height: 1)
        }
    }
}

// MARK: - Blade gauge (HUD)

private struct BladeGauge: View {
    let fillFraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1.5)

                HStack(spacing: 0) {
                    if fillFraction > 0 {
                        LinearGradient(
                            colors: [WhetstoneTheme.blade.opacity(0.5), WhetstoneTheme.blade],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * fillFraction, height: 1.5)
                    }
                    Circle()
                        .fill(WhetstoneTheme.ember)
                        .frame(width: 4, height: 4)
                        .shadow(color: WhetstoneTheme.ember.opacity(0.8), radius: 3)
                        .offset(x: -2)
                        .opacity(fillFraction > 0 ? 1 : 0)
                }
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Honing dots (thinking)

private struct HoningDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(WhetstoneTheme.blade)
                    .frame(width: 10, height: 2)
                    .rotationEffect(.degrees(-12))
                    .opacity(dotOpacity(for: i))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    private func dotOpacity(for i: Int) -> Double {
        let shifted = (phase + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
        return 0.15 + 0.85 * abs(sin(shifted * .pi))
    }
}

// MARK: - Mentor diagram (render_construction SVG)

private struct MentorDiagramBlock: View {
    let payload: SVGPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let trimmed = SVGDiagramSanitizer.embeddedFragment(payload.svg.trimmingCharacters(in: .whitespacesAndNewlines))
            if trimmed.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(WhetstoneTheme.surface)
                    .frame(height: 88)
                    .overlay {
                        Text("Diagram unavailable")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.28))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(WhetstoneTheme.blade.opacity(0.2), lineWidth: 1))
            } else {
                SVGDiagramWebView(svgFragment: trimmed)
                    .frame(maxWidth: 260)
                    .frame(minHeight: 120, idealHeight: 200, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(WhetstoneTheme.blade.opacity(0.22), lineWidth: 1))
            }
            if let caption = payload.caption {
                Text(caption)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
    }
}

// MARK: - Placeholder helper

extension View {
    func placeholder<C: View>(when show: Bool, @ViewBuilder content: () -> C) -> some View {
        ZStack(alignment: .leading) {
            if show { content() }
            self
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(ConversationStore())
        .environmentObject(AuthManager())
}
