import Foundation

private enum ConversationISO8601 {
    /// Postgres / JS `toISOString()` often includes fractional seconds; default `.iso8601` does not.
    static func decodeDate(from decoder: Decoder) throws -> Date {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)

        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let d = basic.date(from: s) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        if let d = df.date(from: s) { return d }

        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date: \(s)")
    }
}

enum ConversationPersistCodec {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom(ConversationISO8601.decodeDate(from:))
        return d
    }()
}

private struct ConversationListEnvelope: Decodable {
    let conversations: [WireConversationSummary]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try c.decodeIfPresent([WireConversationSummary].self, forKey: .conversations) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case conversations
    }
}

struct WireConversationSummary: Decodable {
    let id: UUID
    let title: String
    let totalTokensUsed: Int?
    let createdAt: Date?
    let updatedAt: Date?
}

private struct ConversationDetailEnvelope: Decodable {
    let conversation: WireConversationDetailRecord
}

struct WireConversationDetailRecord: Decodable {
    let id: UUID
    let title: String
    let totalTokensUsed: Int?
    let apiHistory: [WireApiAnyDTO]
    let createdAt: Date?
    let updatedAt: Date?
    let messages: [WireUIMessageRowDTO]

    enum CodingKeys: String, CodingKey {
        case id, title, totalTokensUsed, apiHistory, createdAt, updatedAt, messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        totalTokensUsed = try c.decodeIfPresent(Int.self, forKey: .totalTokensUsed)
        apiHistory = try c.decodeIfPresent([WireApiAnyDTO].self, forKey: .apiHistory) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        messages = try c.decodeIfPresent([WireUIMessageRowDTO].self, forKey: .messages) ?? []
    }
}

struct WireApiAnyDTO: Decodable {
    let role: String
    let content: String?
    let toolCalls: [WireNestedToolCallDTO]?
    let toolCallId: String?
    let imageJpegBase64: [String]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case imageJpegBase64 = "image_jpeg_base64"
    }

    struct WireNestedToolCallDTO: Decodable {
        let id: String
        let type: String
        let function: WireFn

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "function"
            function = try c.decode(WireFn.self, forKey: .function)
        }

        enum CodingKeys: String, CodingKey {
            case id, type, function
        }

        struct WireFn: Decodable {
            let name: String
            let arguments: String

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
                if let s = try? c.decode(String.self, forKey: .arguments) {
                    arguments = s
                } else {
                    // Some APIs emit `arguments` as a JSON object instead of a string.
                    arguments = "{}"
                }
            }

            enum CodingKeys: String, CodingKey {
                case name, arguments
            }
        }
    }
}

struct WireUIMessageRowDTO: Decodable {
    let id: UUID
    let role: String
    let content: String?
    let payload: WireUIMessageExtrasDTO?
}

struct WireUIMessageExtrasDTO: Decodable {
    let attachedImagesB64: [String]?
    let svg: PersistedSvgDTO?
    let meta: PersistedMetaDTO?

    enum CodingKeys: String, CodingKey {
        case attachedImagesB64 = "attached_images_b64"
        case svg, meta
    }
}

struct PersistedSvgDTO: Decodable {
    let svg: String
    let caption: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        svg = try c.decodeIfPresent(String.self, forKey: .svg) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
    }

    enum CodingKeys: String, CodingKey {
        case svg, caption
    }
}

struct PersistedMetaDTO: Decodable {
    let durationSeconds: Double
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }
}

// MARK: - Bridge

enum ConversationHydration {

    static func decodedList(from data: Data) throws -> [WireConversationSummary] {
        try ConversationPersistCodec.decoder.decode(ConversationListEnvelope.self, from: data).conversations
    }

    static func decodedDetail(from data: Data) throws -> WireConversationDetailRecord {
        try ConversationPersistCodec.decoder.decode(ConversationDetailEnvelope.self, from: data).conversation
    }

    static func decodeConversation(from record: WireConversationDetailRecord, systemPrompt: String) throws -> Conversation {
        var conv = Conversation()
        conv.id = record.id
        conv.title = record.title
        conv.totalTokensUsed = record.totalTokensUsed ?? 0
        conv.createdAt = record.createdAt ?? Date()
        conv.updatedAt = record.updatedAt ?? Date()
        conv.apiHistory = record.apiHistory.compactMap(Self.decodeApiMessage)
        conv.messages = try record.messages.map(Self.decodeUIMessageRow)
        conv.apiHistory = stripLegacySystemDuplicates(conv.apiHistory, systemPrompt: systemPrompt)
        return conv
    }

    static func stripLegacySystemDuplicates(_ history: [Message], systemPrompt: String) -> [Message] {
        var out = history
        while out.count >= 2, out[0].role == .system, out[1].role == .system {
            let a = out[0].content ?? ""
            let b = out[1].content ?? ""
            if a == systemPrompt || b == systemPrompt {
                out.removeFirst()
            } else {
                break
            }
        }
        return out
    }

    static func buildPatchJSON(for conversation: Conversation) throws -> Data {
        let hist: [Any] = conversation.apiHistory.map { apiMessageToJSON($0) }
        let ui: [Any] = conversation.messages.map { uiMessageToJSON($0) }
        let dict: [String: Any] = [
            "title": conversation.title,
            "total_tokens_used": conversation.totalTokensUsed,
            "api_history": hist,
            "ui_messages": ui
        ]
        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }

    // MARK: decode API message

    static func decodeApiMessage(_ dto: WireApiAnyDTO) -> Message? {
        let role = dto.role.lowercased()

        if role == "tool" {
            return Message.toolResult(callId: dto.toolCallId ?? "", content: dto.content ?? "")
        }

        let calls: [ToolCall]? = dto.toolCalls?.compactMap { c in
            guard c.type == "function" else { return nil }
            return ToolCall(id: c.id, name: c.function.name, arguments: c.function.arguments)
        }

        switch role {
        case "system":
            return Message.system(dto.content ?? "")
        case "user":
            let imgs = dto.imageJpegBase64?.compactMap { Data(base64Encoded: $0) }
            return Message.user(dto.content ?? "", imageJPEGData: imgs)
        case "assistant":
            return Message.assistant(content: dto.content, toolCalls: calls)
        default:
            return nil
        }
    }

    static func decodeUIMessageRow(_ row: WireUIMessageRowDTO) throws -> ChatMessage {
        let imgs: [Data] = row.payload?.attachedImagesB64?.compactMap { Data(base64Encoded: $0) } ?? []
        let svg: SVGPayload? = {
            guard let s = row.payload?.svg, !s.svg.isEmpty else { return nil }
            return SVGPayload(svg: s.svg, caption: s.caption)
        }()
        let meta: ChatMessage.ResponseMeta? = {
            guard let m = row.payload?.meta else { return nil }
            return ChatMessage.ResponseMeta(
                durationSeconds: m.durationSeconds,
                completionTokens: m.completionTokens,
                totalTokens: m.totalTokens
            )
        }()

        let text = row.content ?? ""

        switch row.role.lowercased() {
        case "user":
            return ChatMessage(id: row.id, role: .user, text: text, attachedImages: imgs, svgPayload: nil, meta: nil)
        case "mentor":
            return ChatMessage(id: row.id, role: .mentor, text: text, attachedImages: [], svgPayload: svg, meta: meta)
        case "tool":
            return ChatMessage(id: row.id, role: .tool, text: text, attachedImages: [], svgPayload: svg, meta: meta)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown ui role \(row.role)"))
        }
    }

    // MARK: encode for PATCH

    private static func apiMessageToJSON(_ m: Message) -> [String: Any] {
        var d: [String: Any] = ["role": m.role.rawValue]
        if let c = m.content { d["content"] = c }
        if let id = m.toolCallId { d["tool_call_id"] = id }
        if let calls = m.toolCalls, !calls.isEmpty {
            d["tool_calls"] = calls.map { c -> [String: Any] in
                [
                    "id": c.id,
                    "type": "function",
                    "function": [
                        "name": c.name,
                        "arguments": c.arguments
                    ]
                ]
            }
        }
        if m.role == .user, let imgs = m.imageJPEGData, !imgs.isEmpty {
            d["image_jpeg_base64"] = imgs.map { $0.base64EncodedString() }
        }
        return d
    }

    private static func uiMessageToJSON(_ msg: ChatMessage) -> [String: Any] {
        var payload: [String: Any]? = nil
        switch msg.role {
        case .user:
            if !msg.attachedImages.isEmpty {
                payload = [
                    "attached_images_b64": msg.attachedImages.map { $0.base64EncodedString() }
                ]
            }
        case .mentor, .tool:
            if msg.svgPayload != nil || msg.meta != nil {
                var p = [String: Any]()
                if let s = msg.svgPayload {
                    p["svg"] = ["svg": s.svg, "caption": s.caption as Any]
                }
                if let m = msg.meta {
                    p["meta"] = [
                        "duration_seconds": m.durationSeconds,
                        "completion_tokens": m.completionTokens,
                        "total_tokens": m.totalTokens
                    ]
                }
                if !p.isEmpty { payload = p }
            }
        }
        let roleKey: String
        switch msg.role {
        case .user: roleKey = "user"
        case .mentor: roleKey = "mentor"
        case .tool: roleKey = "tool"
        }
        var row: [String: Any] = [
            "id": msg.id.uuidString,
            "role": roleKey,
            "content": msg.text
        ]
        if let payload {
            row["payload"] = payload
        }
        return row
    }
}

struct WireConversationCreateBody: Encodable {
    let id: UUID
    let title: String
}
