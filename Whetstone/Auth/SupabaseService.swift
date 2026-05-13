import Foundation
import Supabase

/// Shared Supabase client (anon key). `client` is nil when Supabase keys are not in the bundle.
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient?

    private init() {
        let urlString = WhetstoneConstants.supabaseURL
        guard WhetstoneConstants.isSupabaseConfigured,
              let url = URL(string: urlString),
              let host = url.host, !host.isEmpty
        else {
            client = nil
            return
        }
        // Opt into post–PR-822 behavior: initial session reflects locally stored session consistently.
        // When doing so, treat tokens as possibly expired until refreshed — see `bearerToken()`.
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: WhetstoneConstants.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }
}
