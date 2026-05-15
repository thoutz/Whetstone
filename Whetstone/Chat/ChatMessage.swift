import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let text: String
    let attachedImages: [Data]
    let svgPayload: SVGPayload?
    let meta: ResponseMeta?

    enum Role { case user, mentor, tool }

    struct ResponseMeta {
        let durationSeconds: Double
        let completionTokens: Int
        let totalTokens: Int
    }

    init(id: UUID = UUID(), role: Role, text: String, attachedImages: [Data] = [], svgPayload: SVGPayload? = nil, meta: ResponseMeta? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.attachedImages = attachedImages
        self.svgPayload = svgPayload
        self.meta = meta
    }

    static func user(_ text: String, images: [Data] = []) -> ChatMessage {
        ChatMessage(role: .user, text: text, attachedImages: images, svgPayload: nil, meta: nil)
    }

    static func mentor(_ text: String, svg: SVGPayload? = nil, meta: ResponseMeta? = nil) -> ChatMessage {
        ChatMessage(role: .mentor, text: text, attachedImages: [], svgPayload: svg, meta: meta)
    }

    /// Student turns can be edited from the transcript (truncates history from that turn and resends).
    var isUserTurn: Bool { role == .user }
}
