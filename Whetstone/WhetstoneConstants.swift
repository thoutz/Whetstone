import Foundation

struct WhetstoneConstants {
    static let appName    = "Whetstone"
    static let bundleID   = "com.thoutz.whetstone"

    /// Read from Info.plist key `SupabaseURL` (set in Xcode build settings or xcconfig).
    static var supabaseURL: String {
        let fromPlist = (Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromPlist.isEmpty { return trimQuotes(fromPlist) }
        #if DEBUG
        return trimQuotes(
            (ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        #else
        return ""
        #endif
    }

    /// Anon (public) key only — never the service role key.
    static var supabaseAnonKey: String {
        let fromPlist = (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromPlist.isEmpty { return trimQuotes(fromPlist) }
        #if DEBUG
        return trimQuotes(
            (ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        #else
        return ""
        #endif
    }

    static var isSupabaseConfigured: Bool {
        guard let url = URL(string: supabaseURL),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return false }
        return !supabaseAnonKey.isEmpty
    }

    /// HTTPS origin only (scheme + host) — used for VPS conversation sync beside `AI_BASE_URL`.
    /// Same host as Groq proxy: `AI_BASE_URL` must be parsable HTTPS.
    static var syncHTTPSOrigin: String? {
        let raw = aiBaseURLTrimmedRaw
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return "https://\(host)"
    }

    /// Base path for Postgres-backed conversation API (`/whetstone/api/...`).
    static var conversationsAPIBaseURL: String? {
        guard let origin = syncHTTPSOrigin else { return nil }
        return "\(origin)/whetstone/api"
    }

    /// Raw `AI_BASE_URL` plist / env (trimmed quotes).
    private static var aiBaseURLTrimmedRaw: String {
        let env = ProcessInfo.processInfo.environment
        let fromPlist = (Bundle.main.object(forInfoDictionaryKey: "AI_BASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromPlist.isEmpty { return trimQuotes(fromPlist) }
        #if DEBUG
        return trimQuotes((env["AI_BASE_URL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        return ""
        #endif
    }

    private static func trimQuotes(_ s: String) -> String {
        var t = s
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) ||
           (t.hasPrefix("'")  && t.hasSuffix("'")),
           t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
