import Foundation
import SwiftUI

/// Ephemeral chip UI tied to one conversation so sidebar switches never show stale chips.
struct PendingChipOffer: Equatable {
    let conversationId: UUID
    let payload: ChipsPayload
}

@MainActor
final class ConversationStore: ObservableObject {

    // MARK: - Published state

    @Published var conversations: [Conversation] = []
    /// User-created project folders (device-local until a projects API exists).
    @Published var projects: [Project] = []
    @Published var activeId: UUID?
    @Published var sidebarOpen = false
    @Published var isThinking = false
    @Published var errorBanner: String?
    /// Shown above the input bar until the user sends any message or taps Other.
    @Published private(set) var pendingChipOffer: PendingChipOffer?

    /// Chip strip uses this so switching conversations never shows another thread's chips.
    var visibleChipPayload: ChipsPayload? {
        guard let offer = pendingChipOffer, offer.conversationId == activeId else { return nil }
        return offer.payload
    }

    /// True once the user passes the Login gate — Postgres sync must never run until then (no JWT exists).
    private var remotePersistenceEnabled = false { didSet {} }

    // MARK: - Private

    private let client: AIClient
    private let systemPrompt: String

    private var shouldSyncRemote: Bool {
        remotePersistenceEnabled
            && SupabaseService.shared.client != nil
            && WhetstoneConstants.conversationsAPIBaseURL != nil
    }

    // MARK: - Init

    init() {
        systemPrompt = Self.loadSystemPrompt()
        do {
            client = try makeAIClient()
        } catch {
            client = NoopAIClient()
            errorBanner = error.localizedDescription
        }
        startFresh()
    }

    // MARK: - Auth lifecycle

    func applyAuthenticatedTransition(isAuthenticated: Bool) async {
        remotePersistenceEnabled = isAuthenticated && WhetstoneConstants.conversationsAPIBaseURL != nil
        guard isAuthenticated else {
            resetAfterLogout()
            return
        }
        await hydrateRemote()
    }

    private func resetAfterLogout() {
        pendingChipOffer = nil
        conversations.removeAll()
        projects.removeAll()
        activeId = nil
        startFresh()
    }

    private func hydrateRemote() async {
        guard shouldSyncRemote else { return }

        pendingChipOffer = nil
        let promptSnapshot = systemPrompt

        do {
            // One refresh + one Authorization header for the whole hydrate — parallel detail tasks must not each call `refreshSession`.
            let authHeader = try await ConversationsAPIClient.authorizationHeaderValue()
            let summaries = try await ConversationsAPIClient.fetchConversationSummaries(authorizationHeader: authHeader)

            guard !summaries.isEmpty else {
                conversations.removeAll()
                activeId = nil
                startFreshSynced()
                return
            }

            var bucket: [(Int, Conversation)] = []
            bucket.reserveCapacity(summaries.count)

            try await withThrowingTaskGroup(of: (Int, Conversation).self) { group in
                for item in summaries.enumerated() {
                    group.addTask {
                        let (i, summary) = item
                        let record = try await ConversationsAPIClient.fetchConversationDetail(
                            id: summary.id,
                            authorizationHeader: authHeader
                        )
                        let decoded = try ConversationHydration.decodeConversation(
                            from: record,
                            systemPrompt: promptSnapshot
                        )
                        return (i, decoded)
                    }
                }
                for try await row in group {
                    bucket.append(row)
                }
            }

            conversations = bucket.sorted { $0.0 < $1.0 }.map(\.1)
            activeId = conversations.first?.id
            sidebarOpen = false
        } catch {
            errorBanner = "Could not load your conversations: \(error.localizedDescription)"
            conversations.removeAll()
            activeId = nil
            startFreshSynced()
        }
    }

    // MARK: - Active conversation accessors

    var active: Conversation? {
        conversations.first { $0.id == activeId }
    }

    var messages: [ChatMessage] {
        active?.messages ?? []
    }

    var contextFraction: Double {
        let used = active?.totalTokensUsed ?? 0
        return min(Double(used) / Double(WhetstoneTheme.contextWindowTokens), 1.0)
    }

    var contextPercentString: String {
        String(format: "%.1f%%", contextFraction * 100)
    }

    /// Warning band for Option A — HUD gauge at or above this fraction.
    var isNearContextLimit: Bool {
        contextFraction >= Self.contextLimitWarnFraction
    }

    /// Auto-fork threshold for Option B — send routes to a fresh conversation with handoff context.
    var isAtContextLimit: Bool {
        contextFraction >= Self.contextLimitForkFraction
    }

    /// Banner: warn between warn threshold and fork threshold.
    var shouldOfferContextLimitBanner: Bool {
        isNearContextLimit && !isAtContextLimit
    }

    // MARK: - Conversation management

    func newConversation() {
        pendingChipOffer = nil
        let c = Conversation()
        conversations.insert(c, at: 0)
        activeId = c.id
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            sidebarOpen = false
        }
        scheduleCreateRemote(for: c)
    }

    func select(_ id: UUID) {
        pendingChipOffer = nil
        activeId = id
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            sidebarOpen = false
        }
    }

    func delete(_ id: UUID) {
        pendingChipOffer = nil
        let deletedId = id
        conversations.removeAll { $0.id == deletedId }
        if activeId == deletedId {
            if let first = conversations.first {
                activeId = first.id
            } else {
                startFresh()
            }
        }

        guard shouldSyncRemote else { return }
        Task {
            try? await ConversationsAPIClient.deleteConversation(id: deletedId)
        }
    }

    func setPinned(_ id: UUID, pinned: Bool) {
        guard let idx = index(of: id) else { return }
        conversations[idx].isPinned = pinned
        conversations[idx].updatedAt = Date()
        schedulePersist(conversationId: id)
    }

    func renameConversation(_ id: UUID, to newTitle: String) {
        guard let idx = index(of: id) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversations[idx].title = String(trimmed.prefix(256))
        conversations[idx].updatedAt = Date()
        schedulePersist(conversationId: id)
    }

    func assignToProject(_ conversationId: UUID, projectId: UUID?) {
        guard let idx = index(of: conversationId) else { return }
        conversations[idx].projectId = projectId
        conversations[idx].updatedAt = Date()
        schedulePersist(conversationId: conversationId)
    }

    @discardableResult
    func createProject(name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: String(trimmed.prefix(120)))
        projects.append(project)
        projects.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return project
    }

    // MARK: - Grouped sidebar data

    /// Sidebar renders pinned first, then chronological buckets, then per-project groups (same conversation may appear in multiple sections).
    var sidebarSections: [(sectionId: String, label: String, items: [Conversation])] {
        let nonempty: (Conversation) -> Bool = { !$0.isEmpty }
        var out: [(String, String, [Conversation])] = []

        let pinnedItems = conversations
            .filter { $0.isPinned && nonempty($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !pinnedItems.isEmpty {
            out.append(("section.pinned", "Pinned", pinnedItems))
        }

        for (label, items) in timeGroupedBuckets {
            let filtered = items.filter(nonempty)
            if !filtered.isEmpty {
                out.append(("section.time.\(label)", label, filtered))
            }
        }

        for project in projects {
            let items = conversations
                .filter { $0.projectId == project.id && nonempty($0) }
                .sorted { $0.updatedAt > $1.updatedAt }
            if !items.isEmpty {
                out.append(("section.project.\(project.id.uuidString)", project.name, items))
            }
        }

        return out
    }

    private var timeGroupedBuckets: [(label: String, items: [Conversation])] {
        var buckets: [String: [Conversation]] = [:]
        let orderedKeys = ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days"]
        var monthKeys: [String] = []

        for conv in conversations {
            let key = conv.timeGroup
            buckets[key, default: []].append(conv)
            if !orderedKeys.contains(key), !monthKeys.contains(key) {
                monthKeys.append(key)
            }
        }

        var result: [(String, [Conversation])] = []
        for key in orderedKeys {
            if let items = buckets[key] { result.append((key, items)) }
        }
        for key in monthKeys {
            if let items = buckets[key] { result.append((key, items)) }
        }
        return result
    }

    // MARK: - Send

    func send(_ text: String, imageJPEGData: [Data] = [], isCameraCapture: Bool = false) {
        pendingChipOffer = nil

        guard let idx = activeIndex else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !imageJPEGData.isEmpty else { return }
        errorBanner = nil

        let displayText = trimmed
        let apiText: String
        if trimmed.isEmpty, !imageJPEGData.isEmpty {
            apiText = "(Student attached a photo with no caption.)"
        } else {
            apiText = trimmed
        }

        if isAtContextLimit {
            forkIntoNewConversation(
                oldConversationIndex: idx,
                userDisplayText: displayText,
                apiText: apiText,
                imageJPEGData: imageJPEGData,
                isCameraCapture: isCameraCapture
            )
            return
        }

        conversations[idx].messages.append(.user(displayText, images: imageJPEGData))
        conversations[idx].apiHistory.append(
            Message.user(apiText, imageJPEGData: imageJPEGData.isEmpty ? nil : imageJPEGData)
        )
        conversations[idx].updatedAt = Date()

        if conversations[idx].title == "New conversation" {
            let titleSeed: String
            if trimmed.isEmpty, !imageJPEGData.isEmpty {
                titleSeed = isCameraCapture ? "[Camera]" : "[Photo]"
            } else {
                titleSeed = trimmed
            }
            conversations[idx].title = String(titleSeed.prefix(48))
        }

        Task { await runLoop(conversationId: conversations[idx].id) }
    }

    func dismissChipOfferForOther() {
        pendingChipOffer = nil
    }

    // MARK: - Context limit (fork)

    private static let contextLimitWarnFraction: Double = 0.80
    private static let contextLimitForkFraction: Double = 0.95
    private static let contextLimitHandoffLineCount = 6

    /// Moves the in-flight user send into a new conversation with a short transcript handoff (Option B).
    private func forkIntoNewConversation(
        oldConversationIndex: Int,
        userDisplayText: String,
        apiText: String,
        imageJPEGData: [Data],
        isCameraCapture: Bool
    ) {
        let snapshot = Self.handoffTranscript(from: conversations[oldConversationIndex].messages)

        newConversation()

        guard let newIdx = activeIndex else { return }

        let handoffBody: String
        if snapshot.isEmpty {
            handoffBody = "This is a continuation of a previous session; the prior thread reached the conversation memory limit."
        } else {
            handoffBody = "This is a continuation of a previous session. Here is recent context:\n\n\(snapshot)"
        }
        conversations[newIdx].apiHistory.append(.system(handoffBody))

        conversations[newIdx].messages.append(.user(userDisplayText, images: imageJPEGData))
        conversations[newIdx].apiHistory.append(
            Message.user(apiText, imageJPEGData: imageJPEGData.isEmpty ? nil : imageJPEGData)
        )
        conversations[newIdx].updatedAt = Date()

        if conversations[newIdx].title == "New conversation" {
            let titleSeed: String
            if userDisplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !imageJPEGData.isEmpty {
                titleSeed = isCameraCapture ? "[Camera]" : "[Photo]"
            } else {
                titleSeed = userDisplayText
            }
            conversations[newIdx].title = String(titleSeed.prefix(48))
        }

        guard let newId = activeId else { return }
        Task { await runLoop(conversationId: newId) }
    }

    private static func handoffTranscript(from messages: [ChatMessage]) -> String {
        let slice = messages.suffix(contextLimitHandoffLineCount)
        var lines: [String] = []
        lines.reserveCapacity(slice.count)
        for msg in slice {
            switch msg.role {
            case .user:
                let trimmedText = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    if !msg.attachedImages.isEmpty {
                        lines.append("Student: [Photo attached]")
                    }
                } else {
                    lines.append("Student: \(trimmedText)")
                }
            case .mentor:
                let trimmedText = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    lines.append("Mentor: \(trimmedText)")
                } else if msg.svgPayload != nil {
                    lines.append("Mentor: [Diagram]")
                }
            case .tool:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Remote sync

    private func scheduleCreateRemote(for conversation: Conversation) {
        guard shouldSyncRemote else { return }
        Task {
            do {
                try await ConversationsAPIClient.createConversation(id: conversation.id, title: conversation.title)
            } catch {
                await MainActor.run {
                    errorBanner = "Could not create conversation on server: \(error.localizedDescription)"
                }
            }
        }
    }

    private func schedulePersist(conversationId: UUID) {
        guard shouldSyncRemote else { return }
        Task { await persistConversation(conversationId) }
    }

    private func persistConversation(_ conversationId: UUID) async {
        guard let idx = index(of: conversationId) else { return }
        let snapshot = conversations[idx]
        do {
            let data = try ConversationHydration.buildPatchJSON(for: snapshot)
            try await ConversationsAPIClient.patchConversation(id: conversationId, body: data)
        } catch {
            await MainActor.run {
                errorBanner = "Save sync failed — your chats are cached on device only: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Agentic loop

    private func runLoop(conversationId: UUID) async {
        isThinking = true
        defer { isThinking = false }

        guard let idx = index(of: conversationId) else { return }
        var systemHistory: [Message] = [.system(systemPrompt)] + conversations[idx].apiHistory

        while true {
            let started = Date()
            let completion: Completion
            do {
                completion = try await client.complete(messages: systemHistory, tools: MentorTools.all)
            } catch {
                errorBanner = error.localizedDescription
                schedulePersist(conversationId: conversationId)
                return
            }

            guard let idx = index(of: conversationId) else { return }
            let elapsed = Date().timeIntervalSince(started)

            let assistantMsg = Message.assistant(
                content: completion.content,
                toolCalls: completion.toolCalls.isEmpty ? nil : completion.toolCalls
            )
            conversations[idx].apiHistory.append(assistantMsg)
            systemHistory.append(assistantMsg)

            if let usage = completion.usage {
                conversations[idx].totalTokensUsed += usage.totalTokens
            }
            conversations[idx].updatedAt = Date()

            if let text = completion.content, !text.isEmpty {
                let meta = completion.usage.map { u in
                    ChatMessage.ResponseMeta(
                        durationSeconds: u.durationSeconds > 0 ? u.durationSeconds : elapsed,
                        completionTokens: u.completionTokens,
                        totalTokens: u.totalTokens
                    )
                }
                conversations[idx].messages.append(.mentor(text, meta: meta))
            }

            guard !completion.toolCalls.isEmpty else {
                schedulePersist(conversationId: conversationId)
                break
            }

            var chipsEmitted = false
            for call in completion.toolCalls {
                let result = dispatchToolCall(call)
                let toolMsg = Message.toolResult(callId: result.callId, content: result.output)
                conversations[idx].apiHistory.append(toolMsg)
                systemHistory.append(toolMsg)
                if let svg = result.svgPayload {
                    conversations[idx].messages.append(.mentor("", svg: svg))
                }
                if let chips = result.chipsPayload {
                    pendingChipOffer = PendingChipOffer(conversationId: conversationId, payload: chips)
                    chipsEmitted = true
                }
            }

                schedulePersist(conversationId: conversationId)

            if chipsEmitted { break }
        }
    }

    // MARK: - Helpers

    private var activeIndex: Int? { index(of: activeId) }

    private func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return conversations.firstIndex { $0.id == id }
    }

    /// Local-only bootstrap (logged out OR before hydrate).
    private func startFresh() {
        let c = Conversation()
        conversations.insert(c, at: 0)
        activeId = c.id
    }

    /// After login with an empty server — create the default thread remotely too.
    private func startFreshSynced() {
        startFresh()
        if let conv = conversations.first {
            scheduleCreateRemote(for: conv)
        }
    }

    private static func loadSystemPrompt() -> String {
        guard let url = Bundle.main.url(forResource: "system_prompt", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "You are Whetstone, a demanding mentor who teaches craft." }
        return text
    }
}

private final class NoopAIClient: AIClient {
    func complete(messages: [Message], tools: [Tool]) async throws -> Completion {
        throw AIError.missingAPIKey
    }
}
