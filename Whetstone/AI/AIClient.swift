import Foundation

// MARK: - Wire types (OpenAI-compatible)

struct Message {
    enum Role: String { case system, user, assistant, tool }

    let role: Role
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    /// JPEG segments for user vision turns (OpenAI-style `image_url` parts). Unused for other roles.
    let imageJPEGData: [Data]?

    static func system(_ text: String) -> Message {
        Message(role: .system, content: text, toolCalls: nil, toolCallId: nil, imageJPEGData: nil)
    }
    static func user(_ text: String, imageJPEGData: [Data]? = nil) -> Message {
        Message(role: .user, content: text, toolCalls: nil, toolCallId: nil, imageJPEGData: imageJPEGData)
    }
    static func assistant(content: String?, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: .assistant, content: content, toolCalls: toolCalls, toolCallId: nil, imageJPEGData: nil)
    }
    static func toolResult(callId: String, content: String) -> Message {
        Message(role: .tool, content: content, toolCalls: nil, toolCallId: callId, imageJPEGData: nil)
    }
}

struct ToolCall {
    let id: String
    let name: String
    let arguments: String
}

struct Tool {
    let name: String
    let description: String
    let parameters: [String: Any]
}

struct Completion {
    let content: String?
    let toolCalls: [ToolCall]
    let usage: CompletionUsage?
}

struct CompletionUsage {
    let completionTokens: Int
    let totalTokens: Int
    let durationSeconds: Double  // from x_groq.usage.total_time
}

// MARK: - Protocol

protocol AIClient: AnyObject {
    func complete(messages: [Message], tools: [Tool]) async throws -> Completion
}

// MARK: - Factory

enum AIError: LocalizedError {
    case httpError(Int, String)
    case decodingFailed
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            let detail = Self.summarizeHTTPBody(body)
            switch code {
            case 429, 502, 503:
                return "Service busy (\(code)): \(detail)"
            default:
                return "HTTP \(code): \(detail)"
            }
        case .decodingFailed: return "Failed to decode AI response"
        case .missingAPIKey:
            return "AI not configured: set AI_BASE_URL in Info.plist to your HTTPS proxy (Groq key stays on the server). For emergency debugging only, AI_API_KEY can be set in the Xcode Run scheme — never required for a shipped install."
        }
    }

    /// Pulls Groq/OpenAI-style `{"error":{"message":"…"}}` into a single readable line when possible.
    static func summarizeHTTPBody(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            if trimmed.count <= 420 { return trimmed.isEmpty ? "(no body)" : trimmed }
            return String(trimmed.prefix(420)) + "…"
        }
        if let dict = obj as? [String: Any],
           let err = dict["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return msg
        }
        if let dict = obj as? [String: Any], let msg = dict["message"] as? String {
            return msg
        }
        if trimmed.count <= 420 { return trimmed }
        return String(trimmed.prefix(420)) + "…"
    }
}

private func infoPlistString(_ key: String) -> String? {
    Bundle.main.object(forInfoDictionaryKey: key) as? String
}

func makeAIClient() throws -> AIClient {
    let env = ProcessInfo.processInfo.environment
    let model = env["AI_MODEL"] ?? infoPlistString("AI_MODEL") ?? defaultModel(for: "groq")

    let baseTrimmed = (env["AI_BASE_URL"] ?? infoPlistString("AI_BASE_URL"))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if !baseTrimmed.isEmpty {
        guard let url = URL(string: baseTrimmed) else {
            throw AIError.httpError(0, "Invalid AI_BASE_URL")
        }
        let token = (env["AI_APP_TOKEN"] ?? infoPlistString("AI_APP_TOKEN"))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return OpenAIChatClient(endpoint: url, model: model, bearerToken: token)
    }

    let providerName = env["AI_PROVIDER"] ?? "groq"
    let apiKey = env["AI_API_KEY"] ?? ""

    switch providerName {
    case "groq":
        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw AIError.decodingFailed
        }
        return OpenAIChatClient(endpoint: url, model: model, bearerToken: apiKey)
    default:
        throw AIError.httpError(0, "Provider '\(providerName)' not yet implemented")
    }
}

private func defaultModel(for provider: String) -> String {
    switch provider {
    case "groq":      return "meta-llama/llama-4-scout-17b-16e-instruct"
    case "ollama":    return "llama3"
    case "anthropic": return "claude-sonnet-4-6"
    default:          return "meta-llama/llama-4-scout-17b-16e-instruct"
    }
}
