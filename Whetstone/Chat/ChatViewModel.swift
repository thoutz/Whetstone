import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var errorBanner: String?
    @Published var totalTokensUsed: Int = 0

    private let client: AIClient
    private var history: [Message] = []
    private let systemPrompt: String

    init() {
        systemPrompt = Self.loadSystemPrompt()
        do {
            client = try makeAIClient()
        } catch {
            client = NoopClient()
            errorBanner = error.localizedDescription
        }
    }

    var contextFraction: Double {
        min(Double(totalTokensUsed) / Double(WhetstoneTheme.contextWindowTokens), 1.0)
    }

    var contextPercentString: String {
        String(format: "%.1f%%", contextFraction * 100)
    }

    func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        errorBanner = nil

        messages.append(.user(text, images: []))
        history.append(.user(text, imageJPEGData: nil))

        Task { await runLoop() }
    }

    // MARK: - Agentic loop

    private func runLoop() async {
        isThinking = true
        defer { isThinking = false }

        var systemHistory: [Message] = [.system(systemPrompt)] + history

        while true {
            let started = Date()
            let completion: Completion
            do {
                completion = try await client.complete(
                    messages: systemHistory,
                    tools: MentorTools.all
                )
            } catch {
                errorBanner = error.localizedDescription
                return
            }

            let elapsed = Date().timeIntervalSince(started)

            let assistantMsg = Message.assistant(
                content: completion.content,
                toolCalls: completion.toolCalls.isEmpty ? nil : completion.toolCalls
            )
            history.append(assistantMsg)
            systemHistory.append(assistantMsg)

            if let usage = completion.usage {
                totalTokensUsed += usage.totalTokens
            }

            if let text = completion.content, !text.isEmpty {
                let meta = completion.usage.map { u in
                    ChatMessage.ResponseMeta(
                        durationSeconds: u.durationSeconds > 0 ? u.durationSeconds : elapsed,
                        completionTokens: u.completionTokens,
                        totalTokens: u.totalTokens
                    )
                }
                messages.append(.mentor(text, meta: meta))
            }

            guard !completion.toolCalls.isEmpty else { break }

            for call in completion.toolCalls {
                let result = dispatchToolCall(call)
                let toolMsg = Message.toolResult(callId: result.callId, content: result.output)
                history.append(toolMsg)
                systemHistory.append(toolMsg)

                if let svg = result.svgPayload {
                    messages.append(.mentor("", svg: svg))
                }
            }
        }
    }

    // MARK: - Helpers

    private static func loadSystemPrompt() -> String {
        guard let url = Bundle.main.url(forResource: "system_prompt", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "You are Whetstone, a demanding mentor who teaches craft."
        }
        return text
    }
}

private final class NoopClient: AIClient {
    func complete(messages: [Message], tools: [Tool]) async throws -> Completion {
        throw AIError.missingAPIKey
    }
}
