import Foundation
import Supabase

/// REST client for Postgres-backed conversations on the VPS (`/whetstone/api`).
enum ConversationsAPIClient {

    enum APIError: LocalizedError {
        case missingBaseURL
        case noSupabaseSession
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                return "Conversation sync unavailable: invalid AI_BASE_URL host."
            case .noSupabaseSession:
                return "Not signed in — cannot sync conversations."
            case .http(let code, let body):
                return "Conversation API (\(code)): \(body)"
            }
        }
    }

    static func bearerToken() async throws -> String {
        guard let client = SupabaseService.shared.client else {
            throw APIError.noSupabaseSession
        }
        let session = try await client.auth.session
        // SDK-provided margin (~30s); required when `emitLocalSessionAsInitialSession` is true (supabase-swift PR #822).
        if session.isExpired {
            do {
                let fresh = try await client.auth.refreshSession()
                return fresh.accessToken
            } catch {
                throw APIError.noSupabaseSession
            }
        }
        return session.accessToken
    }

    /// Full `Authorization` header value for reuse across parallel requests (avoids concurrent `refreshSession` races).
    static func authorizationHeaderValue() async throws -> String {
        "Bearer \(try await bearerToken())"
    }

    private static func request(
        path: String,
        method: String,
        body: Data? = nil,
        auth: String
    ) throws -> URLRequest {
        guard let base = WhetstoneConstants.conversationsAPIBaseURL,
              let url = URL(string: base + path) else {
            throw APIError.missingBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }


    /// GET /conversations
    static func fetchConversationSummaries() async throws -> [WireConversationSummary] {
        let auth = try await authorizationHeaderValue()
        return try await fetchConversationSummaries(authorizationHeader: auth)
    }

    /// GET /conversations — pass a header from a single `authorizationHeaderValue()` when firing many requests (e.g. hydrate).
    static func fetchConversationSummaries(authorizationHeader auth: String) async throws -> [WireConversationSummary] {
        let req = try request(path: "/conversations", method: "GET", auth: auth)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw APIError.http(0, "No response") }
        guard http.statusCode == 200 else {
            let msg = summarizeErrorBody(data)
            throw APIError.http(http.statusCode, msg)
        }
        return try ConversationHydration.decodedList(from: data)
    }

    /// GET /conversations/:id (includes `messages` + `apiHistory`)
    static func fetchConversationDetail(id: UUID) async throws -> WireConversationDetailRecord {
        let auth = try await authorizationHeaderValue()
        return try await fetchConversationDetail(id: id, authorizationHeader: auth)
    }

    /// GET /conversations/:id — reuse `authorizationHeader` from one refresh for parallel loads.
    static func fetchConversationDetail(id: UUID, authorizationHeader auth: String) async throws -> WireConversationDetailRecord {
        let req = try request(path: "/conversations/\(id.uuidString.lowercased())", method: "GET", auth: auth)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw APIError.http(0, "No response") }
        guard http.statusCode == 200 else {
            let msg = summarizeErrorBody(data)
            throw APIError.http(http.statusCode, msg)
        }
        return try ConversationHydration.decodedDetail(from: data)
    }

    /// POST /conversations
    static func createConversation(id: UUID, title: String) async throws {
        let auth = try await authorizationHeaderValue()
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        let body = try enc.encode(WireConversationCreateBody(id: id, title: title))
        let req = try request(path: "/conversations", method: "POST", body: body, auth: auth)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw APIError.http(0, "No response") }
        guard http.statusCode == 200 else {
            let msg = summarizeErrorBody(data)
            throw APIError.http(http.statusCode, msg)
        }
    }

    /// PATCH /conversations/:id — full transcript + `api_history`
    static func patchConversation(id: UUID, body: Data) async throws {
        let auth = try await authorizationHeaderValue()
        let req = try request(path: "/conversations/\(id.uuidString.lowercased())", method: "PATCH", body: body, auth: auth)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw APIError.http(0, "No response") }
        guard http.statusCode == 200 else {
            let msg = summarizeErrorBody(data)
            throw APIError.http(http.statusCode, msg)
        }
    }

    /// DELETE /conversations/:id
    static func deleteConversation(id: UUID) async throws {
        let auth = try await authorizationHeaderValue()
        let req = try request(path: "/conversations/\(id.uuidString.lowercased())", method: "DELETE", auth: auth)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw APIError.http(0, "No response") }
        guard http.statusCode == 204 || http.statusCode == 200 else {
            let msg = summarizeErrorBody(data)
            throw APIError.http(http.statusCode, msg)
        }
    }

    private static func summarizeErrorBody(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "(no body)"
        return AIError.summarizeHTTPBody(raw)
    }
}