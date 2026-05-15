import SwiftUI
import PhotosUI
import UIKit

private enum ComposerTextMetrics {
    static let minHeight: CGFloat = 30
    static let maxHeight: CGFloat = 120
}

struct ChatView: View {

    @EnvironmentObject var store: ConversationStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var agentModeStore: AgentModeStore
    @EnvironmentObject private var credentialVaultStore: CredentialVaultStore

    @State private var showProfile = false

    /// Dim yellow for Profile affordance (matches plan).
    private static let profileLabelColor = Color(hex: "c8a84b").opacity(0.5)
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var pipSession = CameraPiPSession()
    @State private var pipDragOffset: CGSize = .zero

    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @State private var stagedJPEGs: [Data] = []

    /// Edit-reply composer (long-press a user bubble).
    @State private var editingMessageId: UUID?
    @State private var editDraft = ""
    @State private var editStagedJPEGs: [Data] = []
    @FocusState private var editFieldFocused: Bool
    @State private var editPhotoPickerItems: [PhotosPickerItem] = []

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
    /// True once the keyboard has appeared at least once this session; prevents spurious hide-notification side-effects.
    @State private var keyboardIsVisible = false

    /// Cleared when switching threads so the near-limit banner can show again if needed.
    @State private var contextLimitBannerDismissed = false

    @State private var composerContentHeight: CGFloat = ComposerTextMetrics.minHeight
    @State private var editComposerContentHeight: CGFloat = ComposerTextMetrics.minHeight
    /// Last keyboard overlap (pt) used for transcript scroll-along; -1 means unset / keyboard hidden baseline.
    @State private var lastKeyboardOverlapForScroll: CGFloat = -1

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
                if editingMessageId != nil {
                    editMessageComposer
                } else {
                    inputBar
                }
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
                .environmentObject(agentModeStore)
                .environmentObject(credentialVaultStore)
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
            cancelEditingMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let overlap = Self.keyboardOverlap(from: note)
            if overlap > 1 { keyboardIsVisible = true }
            keyboardBottomInset = overlap
            if inputFocused || editFieldFocused, overlap > 1 {
                let prev = lastKeyboardOverlapForScroll
                let baseline = overlap
                // Avoid scrolling the transcript on every sub-pixel keyboard tweak (fixes “slides away” while typing).
                let delta = abs(baseline - max(prev, 0))
                if prev < 0 || delta > 18 {
                    transcriptScrollToBottomTick &+= 1
                    lastKeyboardOverlapForScroll = baseline
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            guard keyboardIsVisible else { return }
            keyboardIsVisible = false
            keyboardBottomInset = 0
            lastKeyboardOverlapForScroll = -1
        }
    }

    /// Extra scrollable space under the transcript while the composer is focused and the keyboard is visible.
    private var transcriptKeyboardBottomPadding: CGFloat {
        guard inputFocused || editFieldFocused, keyboardBottomInset > 1 else { return 0 }
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

                if agentModeStore.mode == .advanced, auth.isAdvancedUser {
                    Text("ADVANCED")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(WhetstoneTheme.ember.opacity(0.9))
                }

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
                            MessageRow(
                                message: msg,
                                isThinking: store.isThinking,
                                onBeginEditingUserMessage: beginEditingMessage
                            )
                                .id(msg.id)
                        }
                        if store.isThinking {
                            ThinkingRow()
                                .id("thinking-anchor")
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                .scrollDismissesKeyboard(.never)
                .onPreferenceChange(ChatScrollViewportBottomKey.self) { y in
                    DispatchQueue.main.async {
                        scrollViewportBottomGlobalY = y
                        refreshJumpToLatestVisibility()
                    }
                }
                .onPreferenceChange(ChatTranscriptBottomKey.self) { y in
                    DispatchQueue.main.async {
                        chatTranscriptBottomGlobalY = y
                        refreshJumpToLatestVisibility()
                    }
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
                .onChange(of: editFieldFocused) { _, focused in
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
                .onChange(of: store.isThinking) { _, thinking in
                    showJumpToLatest = false
                    if thinking {
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.28)) {
                                proxy.scrollTo("thinking-anchor", anchor: .bottom)
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.28)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
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

    private var editMessageComposer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(WhetstoneTheme.ember.opacity(0.35))
                .frame(height: 2)

            VStack(spacing: 10) {
                HStack {
                    Text("EDIT MESSAGE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.45))
                    Spacer(minLength: 8)
                    Button("Cancel", action: cancelEditingMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WhetstoneTheme.blade)
                        .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    PhotosPicker(
                        selection: $editPhotoPickerItems,
                        maxSelectionCount: AttachmentLimits.maxImages,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.white.opacity(editStagedJPEGs.count >= AttachmentLimits.maxImages ? 0.15 : 0.42))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(store.isThinking || editStagedJPEGs.count >= AttachmentLimits.maxImages)
                    .accessibilityLabel("Choose photo from library")

                    Spacer()
                }

                if !editStagedJPEGs.isEmpty {
                    editStagedAttachmentsStrip
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ZStack(alignment: .leading) {
                        if editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("›  add missing context…")
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.2))
                                .padding(.leading, 1)
                                .allowsHitTesting(false)
                        }

                        PastableTextEditor(
                            text: $editDraft,
                            contentHeight: $editComposerContentHeight,
                            isFocused: Binding(
                                get: { editFieldFocused },
                                set: { editFieldFocused = $0 }
                            ),
                            keyboardHookTick: composerKeyboardHookTick,
                            accessibilityIdentifier: "whetstoneEditComposerField",
                            isEnabled: !store.isThinking,
                            onImagePasted: { jpeg in
                                guard editStagedJPEGs.count < AttachmentLimits.maxImages else { return }
                                editStagedJPEGs.append(jpeg)
                            }
                        )
                        .frame(height: editComposerContentHeight, alignment: .topLeading)

                        ComposerAsciiKeyboardHook(tick: composerKeyboardHookTick, isFocused: editFieldFocused)
                            .frame(width: 4, height: 4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    StrikeButton(active: canCommitEdit && !store.isThinking, action: commitEditingMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(WhetstoneTheme.obsidian)
            .onChange(of: editPhotoPickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadEditPhotos(from: items) }
            }
        }
    }

    private var editStagedAttachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(editStagedJPEGs.enumerated()), id: \.offset) { index, data in
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
                            editStagedJPEGs.remove(at: index)
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
                    ZStack(alignment: .leading) {
                        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("›  ready to strike")
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.2))
                                .padding(.leading, 1)
                                .allowsHitTesting(false)
                        }

                        PastableTextEditor(
                            text: $draft,
                            contentHeight: $composerContentHeight,
                            isFocused: Binding(
                                get: { inputFocused },
                                set: { inputFocused = $0 }
                            ),
                            keyboardHookTick: composerKeyboardHookTick,
                            accessibilityIdentifier: "whetstoneChatComposerField",
                            isEnabled: !store.isThinking,
                            onImagePasted: { jpeg in
                                guard stagedJPEGs.count < AttachmentLimits.maxImages else { return }
                                stagedJPEGs.append(jpeg)
                            }
                        )
                        .frame(height: composerContentHeight, alignment: .topLeading)

                        ComposerAsciiKeyboardHook(tick: composerKeyboardHookTick, isFocused: inputFocused)
                            .frame(width: 4, height: 4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

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
        composerContentHeight = ComposerTextMetrics.minHeight
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

    private var canCommitEdit: Bool {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || !editStagedJPEGs.isEmpty) && !store.isThinking
    }

    private func beginEditingMessage(_ message: ChatMessage) {
        guard message.isUserTurn, !store.isThinking else { return }
        inputFocused = false
        editingMessageId = message.id
        editDraft = message.text
        editStagedJPEGs = message.attachedImages
        editComposerContentHeight = ComposerTextMetrics.minHeight
        composerKeyboardHookTick &+= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            editFieldFocused = true
        }
    }

    private func cancelEditingMessage() {
        editingMessageId = nil
        editDraft = ""
        editStagedJPEGs = []
        editPhotoPickerItems = []
        editFieldFocused = false
        editComposerContentHeight = ComposerTextMetrics.minHeight
        composerKeyboardHookTick &+= 1
    }

    private func commitEditingMessage() {
        guard let id = editingMessageId else { return }
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !editStagedJPEGs.isEmpty), !store.isThinking else { return }
        let bundle = editStagedJPEGs
        cancelEditingMessage()
        store.editMessage(id: id, newText: text, newImages: bundle)
    }

    private func loadEditPhotos(from items: [PhotosPickerItem]) async {
        let budget = AttachmentLimits.maxImages - editStagedJPEGs.count
        guard budget > 0 else {
            await MainActor.run { editPhotoPickerItems = [] }
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
            editStagedJPEGs.append(contentsOf: datas)
            editPhotoPickerItems = []
        }
    }

}

/// Multiline composer with image paste interception (UIPasteboard image → staged JPEG attachments).
private final class PastingComposerTextView: UITextView {
    var onImagePasted: ((Data) -> Void)?
    var onBoundsChange: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onBoundsChange?()
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        let imageCandidate: UIImage?
        if let img = pb.image {
            imageCandidate = img
        } else if let imgs = pb.images, let first = imgs.first {
            imageCandidate = first
        } else {
            imageCandidate = nil
        }
        if let ui = imageCandidate,
           let jpeg = AttachmentEncoder.jpeg(from: ui) {
            onImagePasted?(jpeg)
            return
        }
        super.paste(sender)
    }
}

private struct PastableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    @Binding var isFocused: Bool
    var keyboardHookTick: Int
    var accessibilityIdentifier: String
    var isEnabled: Bool
    var onImagePasted: ((Data) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PastingComposerTextView {
        let tv = PastingComposerTextView()
        let coordinator = context.coordinator
        tv.delegate = coordinator
        tv.backgroundColor = .clear
        tv.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        tv.textColor = .white
        tv.tintColor = UIColor(WhetstoneTheme.ember)
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.keyboardType = .asciiCapable
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .yes
        tv.isScrollEnabled = false
        tv.text = text
        tv.accessibilityIdentifier = accessibilityIdentifier
        tv.onImagePasted = onImagePasted
        tv.onBoundsChange = { [weak tv, weak coordinator] in
            guard let tv else { return }
            coordinator?.onTextViewBoundsChanged(tv)
        }
        coordinator.lastLayoutWidth = 0
        return tv
    }

    func updateUIView(_ uiView: PastingComposerTextView, context: Context) {
        context.coordinator.parent = self

        uiView.onImagePasted = onImagePasted
        uiView.isEditable = isEnabled
        uiView.accessibilityIdentifier = accessibilityIdentifier

        uiView.onBoundsChange = { [weak uiView, weak coordinator = context.coordinator] in
            guard let tv = uiView else { return }
            coordinator?.onTextViewBoundsChanged(tv)
        }

        let textChanged = uiView.text != text
        if textChanged {
            uiView.text = text
        }

        let focusChanged =
            context.coordinator.lastSyncedFocus != isFocused
            || context.coordinator.lastSyncedEnabled != isEnabled
            || context.coordinator.lastSyncedHookTick != keyboardHookTick

        if focusChanged {
            context.coordinator.lastSyncedFocus = isFocused
            context.coordinator.lastSyncedEnabled = isEnabled
            context.coordinator.lastSyncedHookTick = keyboardHookTick
            DispatchQueue.main.async {
                context.coordinator.applyFocus(tv: uiView)
                uiView.keyboardType = .asciiCapable
            }
        }

        if textChanged || focusChanged {
            context.coordinator.remeasureContentHeight(uiView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PastableTextEditor
        var lastSyncedFocus: Bool?
        var lastSyncedEnabled: Bool?
        var lastSyncedHookTick: Int?
        /// Width last used for height remeasure (skip redundant layout churn).
        var lastLayoutWidth: CGFloat = -1
        private var programmaticResign = false

        init(_ parent: PastableTextEditor) {
            self.parent = parent
        }

        func onTextViewBoundsChanged(_ tv: UITextView) {
            let w = tv.bounds.width
            guard w > 1, abs(w - lastLayoutWidth) > 0.5 else { return }
            lastLayoutWidth = w
            remeasureContentHeight(tv)
        }

        func remeasureContentHeight(_ tv: UITextView) {
            let w = max(tv.bounds.width, 1)
            tv.layoutManager.ensureLayout(for: tv.textContainer)
            let fitted = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
            let display = min(
                max(fitted, ComposerTextMetrics.minHeight),
                ComposerTextMetrics.maxHeight
            )
            tv.isScrollEnabled = fitted > ComposerTextMetrics.maxHeight + 0.5
            if abs(parent.contentHeight - display) > 0.5 {
                parent.contentHeight = display
            }
        }

        func applyFocus(tv: UITextView) {
            let shouldFocus = parent.isFocused && parent.isEnabled
            if shouldFocus, !tv.isFirstResponder {
                tv.becomeFirstResponder()
            } else if !shouldFocus, tv.isFirstResponder {
                programmaticResign = true
                tv.resignFirstResponder()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            remeasureContentHeight(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if programmaticResign {
                programmaticResign = false
                return
            }
            if parent.isFocused {
                parent.isFocused = false
            }
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
    let isThinking: Bool
    let onBeginEditingUserMessage: (ChatMessage) -> Void

    var body: some View {
        switch message.role {
        case .user:
            UserMessageView(
                message: message,
                isThinking: isThinking,
                onBeginEditingUserMessage: onBeginEditingUserMessage
            )
        case .mentor, .tool:
            MentorMessageView(message: message)
        }
    }
}

// MARK: - User message

private struct UserMessageView: View {
    let message: ChatMessage
    let isThinking: Bool
    let onBeginEditingUserMessage: (ChatMessage) -> Void

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
        .contextMenu {
            if message.isUserTurn, !isThinking {
                Button("Edit message") {
                    onBeginEditingUserMessage(message)
                }
            }
        }
    }
}

// MARK: - In-transcript thinking

private struct ThinkingRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BladeEdge()
                .frame(width: WhetstoneTheme.bladeEdgeWidth + WhetstoneTheme.sparkDotSize)

            VStack(alignment: .leading, spacing: 10) {
                Text("Thinking…")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                HoningDots()
            }

            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mentor is thinking, preparing a response")
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

            mentorContentColumn
                .contextMenu {
                    if let payload = resolvedCopyPayload {
                        Button(payload.menuTitle) {
                            Self.copyToPasteboard(payload.string)
                            copyFeedbackTick &+= 1
                        }
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
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Button {
                        Self.copyToPasteboard(payload.string)
                        copyFeedbackTick &+= 1
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .buttonStyle(MentorCopyAffordanceStyle())
                    .accessibilityLabel(Self.copyAccessibilityLabel(for: message))
                    .accessibilityHint(message.text.isEmpty ? "Copies the diagram caption to the clipboard." : "Copies the mentor reply to the clipboard.")

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

private struct ChatPreviewContainer: View {
    @StateObject private var auth: AuthManager
    @StateObject private var mode: AgentModeStore
    @StateObject private var vault: CredentialVaultStore
    @StateObject private var store: ConversationStore

    init() {
        let a = AuthManager()
        let m = AgentModeStore()
        let v = CredentialVaultStore()
        _auth = StateObject(wrappedValue: a)
        _mode = StateObject(wrappedValue: m)
        _vault = StateObject(wrappedValue: v)
        _store = StateObject(wrappedValue: ConversationStore(agentModeStore: m, auth: a, credentialVaultStore: v))
    }

    var body: some View {
        ChatView()
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(mode)
            .environmentObject(vault)
    }
}

#Preview {
    ChatPreviewContainer()
}
