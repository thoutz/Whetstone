import Foundation

// MARK: - Chips (render_chips tool)

struct Chip: Equatable, Hashable {
    let label: String
    let value: String
}

struct ChipsPayload: Equatable {
    let chips: [Chip]
    let allowMultiSelect: Bool
    let includeOther: Bool
}

// MARK: - Tool catalogue

enum MentorTools {
    static let all: [Tool] = [renderConstruction, renderChips]

    static let renderConstruction = Tool(
        name: "render_construction",
        description: """
            Render an instructional SVG diagram to aid teaching (geometry grids, \
            perspective aids, notation, chord charts, annotation overlays on references \
            the student uploaded — arrows, highlights, callouts). Never representational \
            content that substitutes for the student's own creative or assigned work in \
            any medium (drawing, design draft, composition, etc.).
            """,
        parameters: [
            "type": "object",
            "properties": [
                "svg": [
                    "type": "string",
                    "description": "Complete SVG markup string to display to the student."
                ] as [String: Any],
                "caption": [
                    "type": "string",
                    "description": "Short label shown beneath the diagram (max 80 chars)."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["svg"]
        ] as [String: Any]
    )

    static let renderChips = Tool(
        name: "render_chips",
        description: """
            Show 2–4 tappable response chips when the student's next reply fits a small \
            set of natural options. Always pair with prose in the same turn — chips never \
            appear alone. The student can always type instead; \"Other\" is always offered \
            in the UI when include_other is true. Use for routing and reflection helpers, \
            never to shortcut discipline or replace articulation that must be typed.
            """,
        parameters: [
            "type": "object",
            "properties": [
                "chips": [
                    "type": "array",
                    "description": "2–4 chips. Each chip sends its label as the user's next message when tapped.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "label": [
                                "type": "string",
                                "description": "Short button text shown to the student."
                            ] as [String: Any],
                            "value": [
                                "type": "string",
                                "description": "Stable machine-facing token (may match label)."
                            ] as [String: Any]
                        ] as [String: Any],
                        "required": ["label", "value"]
                    ] as [String: Any]
                ] as [String: Any],
                "allow_multi_select": [
                    "anyOf": [
                        ["type": "boolean"] as [String: Any],
                        ["type": "string"] as [String: Any]
                    ],
                    "description": "If true, UI may allow multiple selections (future). Phase 1 UI uses single tap. Prefer JSON boolean true/false; quoted booleans as strings are accepted."
                ] as [String: Any],
                "include_other": [
                    "anyOf": [
                        ["type": "boolean"] as [String: Any],
                        ["type": "string"] as [String: Any]
                    ],
                    "description": "When true, UI adds an Other escape hatch (recommended default true). Prefer JSON boolean; strings like \"true\"/\"false\" are accepted."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["chips"]
        ] as [String: Any]
    )
}

// MARK: - Dispatch

struct ToolResult {
    let callId: String
    let output: String
    let svgPayload: SVGPayload?
    let chipsPayload: ChipsPayload?
}

struct SVGPayload {
    let svg: String
    let caption: String?
}

func dispatchToolCall(_ call: ToolCall, advancedToolsEnabled: Bool) async -> ToolResult {
    switch call.name {
    case "render_construction":
        return handleRenderConstruction(call)
    case "render_chips":
        return handleRenderChips(call)
    default:
        if advancedToolsEnabled {
            return await AdvancedTools.dispatch(call)
        }
        return ToolResult(
            callId: call.id,
            output: "Unknown tool: \(call.name)",
            svgPayload: nil,
            chipsPayload: nil
        )
    }
}

// MARK: - render_construction

private func handleRenderConstruction(_ call: ToolCall) -> ToolResult {
    guard let data = call.arguments.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return ToolResult(callId: call.id, output: "Invalid arguments", svgPayload: nil, chipsPayload: nil)
    }

    let svg = json["svg"] as? String ?? ""
    let caption = json["caption"] as? String

    print("─────────────────────────────────────")
    print("[render_construction] caption: \(caption ?? "(none)")")
    print(svg)
    print("─────────────────────────────────────")

    let payload = SVGPayload(svg: svg, caption: caption)
    return ToolResult(callId: call.id, output: "Diagram rendered.", svgPayload: payload, chipsPayload: nil)
}

// MARK: - render_chips

/// Groq/OpenAI models sometimes emit `"true"`/`"false"` strings for chip flags; accept Bool, string, or small ints.
private func mentorBool(from value: Any?, default defaultValue: Bool) -> Bool {
    if let b = value as? Bool { return b }
    if let s = value as? String {
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "y": return true
        case "false", "0", "no", "n": return false
        default: return defaultValue
        }
    }
    if let i = value as? Int { return i != 0 }
    return defaultValue
}

private func handleRenderChips(_ call: ToolCall) -> ToolResult {
    guard let data = call.arguments.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let chipsRaw = json["chips"] as? [[String: Any]]
    else {
        return ToolResult(callId: call.id, output: "Invalid render_chips arguments", svgPayload: nil, chipsPayload: nil)
    }

    var chips: [Chip] = []
    for dict in chipsRaw.prefix(4) {
        guard let label = dict["label"] as? String,
              let value = dict["value"] as? String else { continue }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !trimmedValue.isEmpty else { continue }
        chips.append(Chip(label: trimmedLabel, value: trimmedValue))
    }

    guard chips.count >= 2 else {
        return ToolResult(
            callId: call.id,
            output: "render_chips requires at least 2 valid chips with label and value.",
            svgPayload: nil,
            chipsPayload: nil
        )
    }

    let allowMulti = mentorBool(from: json["allow_multi_select"], default: false)
    let includeOther = mentorBool(from: json["include_other"], default: true)

    let payload = ChipsPayload(chips: chips, allowMultiSelect: allowMulti, includeOther: includeOther)
    print("[render_chips] \(chips.count) chips, multi=\(allowMulti), other=\(includeOther)")

    return ToolResult(
        callId: call.id,
        output: "Chips displayed to the student.",
        svgPayload: nil,
        chipsPayload: payload
    )
}
