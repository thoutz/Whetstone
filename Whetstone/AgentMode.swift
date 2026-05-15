import Foundation
import SwiftUI

/// Persisted mentoring vs full technical agent posture. Effective advanced mode still requires Supabase entitlement.
enum AgentMode: String, Codable {
    case standard
    case advanced

    /// Base name inside `Resources/` (without `.txt`).
    private var promptResourceBase: String {
        switch self {
        case .standard: return "system_prompt"
        case .advanced: return "advanced_system_prompt"
        }
    }

    /// System prompt bundled for chat completions (not persisted in API history as a duplicated prefix after hydration sanitization).
    static func bundledPrompt(for mode: AgentMode) -> String {
        guard let url = Bundle.main.url(forResource: mode.promptResourceBase, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return fallbackPrompt(for: mode) }
        return text
    }

    /// Prompt strings used when stripping duplicated legacy `.system` rows after sync.
    static var allBundledPromptStrings: [String] {
        [bundledPrompt(for: .standard), bundledPrompt(for: .advanced)]
    }

    private static func fallbackPrompt(for mode: AgentMode) -> String {
        switch mode {
        case .standard:
            return "You are Whetstone, a demanding mentor who teaches craft."
        case .advanced:
            return """
            You are Whetstone in Advanced Mode — a skilled technical assistant on the student's device \
            with network and SSH tooling. Help safely and obey law and server policy.
            """
        }
    }
}

/// User preference for Advanced Mode (`UserDefaults`). Entitlement comes from AuthManager (`app_metadata.advanced_mode`).
@MainActor
final class AgentModeStore: ObservableObject {
    static let storageKey = "whetstone.agentMode"

    @Published private(set) var mode: AgentMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AgentMode.standard.rawValue
        mode = AgentMode(rawValue: raw) ?? .standard
    }

    /// Call when JWT shows the user lost advanced entitlement — stored preference cannot stay on Advanced.
    func revertToStandardIfNotEntitled(isAdvancedUser: Bool) {
        guard !isAdvancedUser, mode == .advanced else { return }
        mode = .standard
    }

    func setMode(_ newValue: AgentMode) {
        mode = newValue
    }
}
