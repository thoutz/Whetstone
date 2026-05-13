import Foundation

/// OpenAI-compatible chat completions HTTP client (Groq or your own proxy base URL).
final class OpenAIChatClient: AIClient {
    private let endpoint: URL
    private let model: String
    /// Sent as `Authorization: Bearer …` when non-empty (Groq API key or shared app token).
    private let bearerToken: String

    /// Backoff after 429 / 502 / 503 (Groq capacity / upstream / gateway).
    private let retryBackoffNanoseconds: [UInt64] = [
        600_000_000, 1_200_000_000, 2_400_000_000, 4_800_000_000,
    ]

    init(endpoint: URL, model: String, bearerToken: String) {
        self.endpoint = endpoint
        self.model = model
        self.bearerToken = bearerToken
    }

    func complete(messages: [Message], tools: [Tool]) async throws -> Completion {
        let body = buildBody(messages: messages, tools: tools)
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        if !bearerToken.isEmpty {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        var lastStatus = 0
        var lastText = ""

        var attempt = 0
        while true {
            let (responseData, response) = try await URLSession.shared.data(for: req)
            lastStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastText = String(data: responseData, encoding: .utf8) ?? ""

            if lastStatus == 200 {
                return try parseCompletion(responseData)
            }

            let retriable = lastStatus == 429 || lastStatus == 502 || lastStatus == 503
            if retriable, attempt < retryBackoffNanoseconds.count {
                try await Task.sleep(nanoseconds: retryBackoffNanoseconds[attempt])
                attempt += 1
                continue
            }

            throw AIError.httpError(lastStatus, lastText)
        }
    }

    // MARK: - Serialisation

    private func buildBody(messages: [Message], tools: [Tool]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map(serialise)
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map(serialise)
            body["tool_choice"] = "auto"
        }
        return body
    }

    private func serialise(_ message: Message) -> [String: Any] {
        var dict: [String: Any] = ["role": message.role.rawValue]
        if let id = message.toolCallId { dict["tool_call_id"] = id }
        if let calls = message.toolCalls {
            dict["tool_calls"] = calls.map { call -> [String: Any] in
                ["id": call.id,
                 "type": "function",
                 "function": ["name": call.name, "arguments": call.arguments]]
            }
        }

        let images = message.imageJPEGData ?? []
        if message.role == .user, !images.isEmpty {
            var parts: [[String: Any]] = []
            if let raw = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                parts.append(["type": "text", "text": raw])
            }
            for jpeg in images {
                let b64 = jpeg.base64EncodedString()
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                ])
            }
            dict["content"] = parts
        } else if let content = message.content {
            dict["content"] = content
        }

        return dict
    }

    private func serialise(_ tool: Tool) -> [String: Any] {
        ["type": "function",
         "function": [
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.parameters
         ] as [String: Any]]
    }

    // MARK: - Parsing

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct MessagePayload: Decodable {
                let content: String?
                let toolCalls: [RawToolCall]?
                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                }
            }
            let message: MessagePayload
        }
        struct Usage: Decodable {
            let completionTokens: Int
            let totalTokens: Int
            enum CodingKeys: String, CodingKey {
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
            }
        }
        struct XGroq: Decodable {
            struct XUsage: Decodable {
                let totalTime: Double?
                enum CodingKeys: String, CodingKey { case totalTime = "total_time" }
            }
            let usage: XUsage?
        }
        let choices: [Choice]
        let usage: Usage?
        let xGroq: XGroq?
        enum CodingKeys: String, CodingKey {
            case choices, usage
            case xGroq = "x_groq"
        }
    }

    private struct RawToolCall: Decodable {
        struct Function: Decodable { let name: String; let arguments: String }
        let id: String
        let function: Function
    }

    private func parseCompletion(_ data: Data) throws -> Completion {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let choice = decoded.choices.first else { throw AIError.decodingFailed }
        let msg = choice.message
        let calls = (msg.toolCalls ?? []).map { raw in
            ToolCall(id: raw.id, name: raw.function.name, arguments: raw.function.arguments)
        }
        let usage: CompletionUsage? = decoded.usage.map { u in
            CompletionUsage(
                completionTokens: u.completionTokens,
                totalTokens: u.totalTokens,
                durationSeconds: decoded.xGroq?.usage?.totalTime ?? 0
            )
        }
        return Completion(content: msg.content, toolCalls: calls, usage: usage)
    }
}
