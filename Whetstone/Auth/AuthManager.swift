import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading       = false
    @Published var errorMessage: String?
    /// Set from JWT `app_metadata.advanced_mode` (admin-only in Supabase). Drives Profile gate for Advanced Mode.
    @Published private(set) var isAdvancedUser = false

    private(set) var appleSignInNonce: String = ""

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Session restore

    func restoreSession() async {
        guard let client = SupabaseService.shared.client else {
            applyAccessToken(nil)
            return
        }
        do {
            let session = try await client.auth.session
            applyAccessToken(session.accessToken)
            isAuthenticated = true
        } catch {
            applyAccessToken(nil)
            isAuthenticated = false
        }
    }

    /// Re-read entitlement after token refresh without toggling login UI.
    func refreshEntitlementFromSession() async {
        guard let client = SupabaseService.shared.client else {
            applyAccessToken(nil)
            return
        }
        guard let token = try? await client.auth.session.accessToken else {
            applyAccessToken(nil)
            return
        }
        applyAccessToken(token)
    }

    private func applyAccessToken(_ token: String?) {
        guard let token, !token.isEmpty else {
            isAdvancedUser = false
            return
        }
        isAdvancedUser = SupabaseJWTHelper.readAdvancedModeEntitlement(accessToken: token)
    }

    // MARK: - Apple Sign In

    /// Generates a raw nonce, stores it, and returns the SHA-256 hex string for Apple's request.
    func prepareAppleNonce() -> String {
        let raw = (0..<32)
            .map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                .randomElement()! }
            .map(String.init)
            .joined()
        appleSignInNonce = raw
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                throw AppleSignInError.invalidCredential
            }

            guard let client = SupabaseService.shared.client else {
                throw AppleSignInError.supabaseNotConfigured
            }

            try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: appleSignInNonce.isEmpty ? nil : appleSignInNonce
                )
            )

            if let sess = try? await client.auth.session {
                applyAccessToken(sess.accessToken)
            }
            isAuthenticated = true
        } catch {
            applyAccessToken(nil)
            errorMessage = Self.friendlyMessage(error)
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await SupabaseService.shared.client?.auth.signOut(scope: .global)
        applyAccessToken(nil)
        isAuthenticated = false
        errorMessage = nil
    }

    // MARK: - Error copy

    private static func friendlyMessage(_ error: Error) -> String {
        if let e = error as? ASAuthorizationError, e.code == .canceled {
            return "Sign in with Apple was cancelled."
        }
        let ns = error as NSError
        let isAuthServices = ns.domain == ASAuthorizationError.errorDomain
            || ns.domain == "com.apple.AuthenticationServices.AuthorizationError"
        if isAuthServices,
           ns.code == ASAuthorizationError.Code.unknown.rawValue || ns.code == 1000 {
            return """
            Sign in with Apple failed (error 1000).

            • Simulator: sign in with an Apple ID in Settings on the simulator.
            • Device: clean build folder, rebuild with the correct Team ID for \(WhetstoneConstants.bundleID).
            """
        }
        return error.localizedDescription
    }
}

// MARK: - Errors

private enum AppleSignInError: LocalizedError {
    case invalidCredential
    case supabaseNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidCredential:       return "Sign in with Apple didn't return a valid credential."
        case .supabaseNotConfigured:   return "Supabase is not configured. Add SupabaseURL and SupabaseAnonKey to Info.plist."
        }
    }
}
