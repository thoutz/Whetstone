import Foundation
import Security
import SwiftUI

// MARK: - Metadata (no secrets)

struct VaultPasswordEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var nickname: String
    var username: String
    var allowAgentUse: Bool
    var createdAt: Date
    var comment: String?
}

struct VaultSSHIdentity: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var nickname: String
    /// Default SSH username when the tool omits `username` (stored non-secret metadata).
    var defaultUsername: String?
    var allowAgentUse: Bool
    var createdAt: Date
    var comment: String?
    /// Optional pasted public key line for display only.
    var publicKeyDisplay: String?
}

private struct VaultMetadataIndex: Codable {
    var passwords: [VaultPasswordEntry]
    var sshIdentities: [VaultSSHIdentity]

    init(passwords: [VaultPasswordEntry], sshIdentities: [VaultSSHIdentity]) {
        self.passwords = passwords
        self.sshIdentities = sshIdentities
    }

    init() {
        passwords = []
        sshIdentities = []
    }
}

enum CredentialVaultError: LocalizedError, Equatable {
    case entryNotFound
    case agentUseNotAllowed
    case emptySecret
    case keychainFailure(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return "No saved credential with that id."
        case .agentUseNotAllowed:
            return "Saved credential exists but Advanced tools cannot use it (allow agent off)."
        case .emptySecret:
            return "Secret payload is empty."
        case .keychainFailure(let status):
            return "Keychain error (\(status))."
        }
    }
}

// MARK: - Keychain (secrets only)

enum CredentialVaultKeychain {

    /// Bundle-scoped vault; secrets never synced via iCloud keychain backup when using ThisDeviceOnly.
    static var service: String { "\(WhetstoneConstants.bundleID).vault" }

    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static func passwordAccount(for id: UUID) -> String { "password.\(id.uuidString)" }

    private static func sshAccount(for id: UUID) -> String { "sshPrivateKey.\(id.uuidString)" }

    static func setPassword(secret: Data, id: UUID) throws {
        try setGenericPassword(secret: secret, account: passwordAccount(for: id))
    }

    static func setSSHPrivateKey(secret: Data, id: UUID) throws {
        try setGenericPassword(secret: secret, account: sshAccount(for: id))
    }

    static func passwordData(id: UUID) throws -> Data {
        try copyGeneric(account: passwordAccount(for: id))
    }

    static func sshPrivateKeyData(id: UUID) throws -> Data {
        try copyGeneric(account: sshAccount(for: id))
    }

    static func deletePassword(id: UUID) {
        deleteGeneric(account: passwordAccount(for: id))
    }

    static func deleteSSHPrivateKey(id: UUID) {
        deleteGeneric(account: sshAccount(for: id))
    }

    private static func setGenericPassword(secret: Data, account: String) throws {
        guard !secret.isEmpty else { throw CredentialVaultError.emptySecret }

        deleteGeneric(account: account)

        let data = secret as CFData

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false,
        ]

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialVaultError.keychainFailure(status: status)
        }
    }

    private static func copyGeneric(account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data, !data.isEmpty else {
            if status == errSecItemNotFound { throw CredentialVaultError.entryNotFound }
            throw CredentialVaultError.keychainFailure(status: status)
        }
        return data
    }

    private static func deleteGeneric(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Advanced tools resolution (never log secrets)

/// Resolved material for `AdvancedTools`; implementers must enforce `allowAgentUse`.
@MainActor
protocol CredentialVaultProviding: AnyObject {
    func sshPasswordSecretForAgentUse(id: UUID) throws -> String
    func sshPrivateKeyPEMForAgentUse(id: UUID) throws -> String
    func defaultUsernameForSSHIdentity(id: UUID) -> String?
}

extension CredentialVaultProviding {
    func defaultUsernameForSSHIdentity(id: UUID) -> String? { nil }

    func sshPrivateKeyBytesForAgentUse(id: UUID) throws -> Data {
        let pem = try sshPrivateKeyPEMForAgentUse(id: id)
        return Data(pem.utf8)
    }
}

// MARK: - Store

@MainActor
final class CredentialVaultStore: ObservableObject, CredentialVaultProviding {

    private static let defaultsKey = "whetstone.vault.index"

    @Published private(set) var passwords: [VaultPasswordEntry] = []
    @Published private(set) var sshIdentities: [VaultSSHIdentity] = []

    init() {
        loadFromDiskIfNeeded()
    }

    func loadFromDiskIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(VaultMetadataIndex.self, from: data)
        else {
            passwords = []
            sshIdentities = []
            return
        }
        passwords = decoded.passwords.sorted { $0.createdAt < $1.createdAt }
        sshIdentities = decoded.sshIdentities.sorted { $0.createdAt < $1.createdAt }
    }

    func sshPasswordSecretForAgentUse(id: UUID) throws -> String {
        guard let meta = passwords.first(where: { $0.id == id }) else {
            throw CredentialVaultError.entryNotFound
        }
        guard meta.allowAgentUse else { throw CredentialVaultError.agentUseNotAllowed }

        let data = try CredentialVaultKeychain.passwordData(id: id)
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            throw CredentialVaultError.emptySecret
        }
        return s
    }

    func sshPrivateKeyPEMForAgentUse(id: UUID) throws -> String {
        guard let meta = sshIdentities.first(where: { $0.id == id }) else {
            throw CredentialVaultError.entryNotFound
        }
        guard meta.allowAgentUse else { throw CredentialVaultError.agentUseNotAllowed }

        let data = try CredentialVaultKeychain.sshPrivateKeyData(id: id)
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            throw CredentialVaultError.emptySecret
        }
        return s
    }

    func defaultUsernameForSSHIdentity(id: UUID) -> String? {
        sshIdentities.first { $0.id == id }?.defaultUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Profile clipboard only — ignores `allowAgentUse`; never invoked from tools.
    func passwordSecretForClipboard(id: UUID) throws -> String {
        let data = try CredentialVaultKeychain.passwordData(id: id)
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty
        else {
            throw CredentialVaultError.emptySecret
        }
        return s
    }

    // MARK: Password CRUD

    func upsertPassword(
        id: UUID? = nil,
        nickname: String,
        username: String,
        passwordPlain: String?,
        allowAgentUse: Bool,
        comment: String?
    ) throws {
        let trimmedNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNick.isEmpty, !trimmedUser.isEmpty else {
            throw AdvErrVault(message: "Nickname and username required.")
        }

        let uuid = id ?? UUID()
        let isUpdate = passwords.contains(where: { $0.id == uuid })

        let secretProvided = !(passwordPlain?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        if !isUpdate, !secretProvided {
            throw AdvErrVault(message: "Password required for a new saved password.")
        }
        if secretProvided, let pwd = passwordPlain {
            let trimmed = pwd.trimmingCharacters(in: .whitespacesAndNewlines)
            try CredentialVaultKeychain.setPassword(secret: Data(trimmed.utf8), id: uuid)
        } else if isUpdate {
            // Metadata-only refresh; ensure secret still exists so we cannot orphan metadata.
            _ = try CredentialVaultKeychain.passwordData(id: uuid)
        } else {
            throw AdvErrVault(message: "Password required for a new saved password.")
        }

        let entry = VaultPasswordEntry(
            id: uuid,
            nickname: trimmedNick,
            username: trimmedUser,
            allowAgentUse: allowAgentUse,
            createdAt: passwords.first(where: { $0.id == uuid })?.createdAt ?? Date(),
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        if let idx = passwords.firstIndex(where: { $0.id == uuid }) {
            passwords[idx] = entry
        } else {
            passwords.append(entry)
        }
        saveIndex()
    }

    func deletePassword(id: UUID) {
        CredentialVaultKeychain.deletePassword(id: id)
        passwords.removeAll { $0.id == id }
        saveIndex()
    }

    func updatePasswordAllowAgent(id: UUID, allow: Bool) {
        guard let idx = passwords.firstIndex(where: { $0.id == id }) else { return }
        passwords[idx].allowAgentUse = allow
        saveIndex()
    }

    // MARK: SSH CRUD

    func upsertSSHIdentity(
        id: UUID? = nil,
        nickname: String,
        defaultUsername: String?,
        privateKeyPEM: String?,
        allowAgentUse: Bool,
        publicKeyDisplay: String?,
        comment: String?
    ) throws {
        let trimmedNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNick.isEmpty else { throw AdvErrVault(message: "Nickname required.") }

        let uuid = id ?? UUID()
        let isUpdate = sshIdentities.contains(where: { $0.id == uuid })

        let pemProvided = !(privateKeyPEM?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        if pemProvided, let raw = privateKeyPEM {
            let pem = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard pem.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") else {
                throw AdvErrVault(message: "Only OpenSSH private key format is supported.")
            }
            try CredentialVaultKeychain.setSSHPrivateKey(secret: Data(pem.utf8), id: uuid)
        } else if isUpdate {
            _ = try CredentialVaultKeychain.sshPrivateKeyData(id: uuid)
        } else {
            throw AdvErrVault(message: "Private key required for a new SSH identity.")
        }

        let entry = VaultSSHIdentity(
            id: uuid,
            nickname: trimmedNick,
            defaultUsername: defaultUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            allowAgentUse: allowAgentUse,
            createdAt: sshIdentities.first(where: { $0.id == uuid })?.createdAt ?? Date(),
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            publicKeyDisplay: publicKeyDisplay?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        if let idx = sshIdentities.firstIndex(where: { $0.id == uuid }) {
            sshIdentities[idx] = entry
        } else {
            sshIdentities.append(entry)
        }
        saveIndex()
    }

    func deleteSSHIdentity(id: UUID) {
        CredentialVaultKeychain.deleteSSHPrivateKey(id: id)
        sshIdentities.removeAll { $0.id == id }
        saveIndex()
    }

    func sshIdentity(for id: UUID) -> VaultSSHIdentity? {
        sshIdentities.first { $0.id == id }
    }

    func passwordEntry(for id: UUID) -> VaultPasswordEntry? {
        passwords.first { $0.id == id }
    }

    // MARK: - Private

    private func saveIndex() {
        let index = VaultMetadataIndex(passwords: passwords, sshIdentities: sshIdentities)
        if let data = try? JSONEncoder().encode(index) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

private struct AdvErrVault: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
