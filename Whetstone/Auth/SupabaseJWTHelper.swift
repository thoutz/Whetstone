import Foundation

enum SupabaseJWTHelper {

    /// Reads `app_metadata.advanced_mode` from a Supabase access token (JWT) payload.
    static func readAdvancedModeEntitlement(accessToken: String) -> Bool {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return false }
        var segment = String(parts[1])

        segment = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let pad = segment.count % 4
        if pad != 0 { segment.append(String(repeating: "=", count: 4 - pad)) }

        guard let data = Data(base64Encoded: segment),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        guard let meta = json["app_metadata"] as? [String: Any],
              let value = meta["advanced_mode"]
        else { return false }

        switch value {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let d as Double: return d != 0
        case let s as String:
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "y": return true
            default: return false
            }
        default: return false
        }
    }
}
