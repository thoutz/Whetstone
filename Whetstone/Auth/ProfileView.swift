import SwiftUI
import Supabase
import UIKit
import UniformTypeIdentifiers

/// Account sheet — sign out. Email from current Supabase session.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var agentModeStore: AgentModeStore
    @EnvironmentObject private var credentialVaultStore: CredentialVaultStore

    @State private var email: String = ""
    @State private var signingOut = false

    @State private var passwordEditorMode: VaultPasswordEditorMode?
    @State private var sshEditorMode: VaultSSHEditorMode?
    @State private var deletePasswordConfirm: VaultPasswordEntry?
    @State private var deleteSSHConfirm: VaultSSHIdentity?

    private var vaultVisible: Bool {
        auth.isAdvancedUser && agentModeStore.mode == .advanced
    }

    private var advancedToggleBinding: Binding<Bool> {
        Binding(
            get: { agentModeStore.mode == .advanced },
            set: { on in
                agentModeStore.setMode(on ? .advanced : .standard)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhetstoneTheme.obsidian.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text("Signed in")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .tracking(1.6)

                            Text(emailDisplay)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            if showsApplePrivateSubtitle {
                                Text("Apple hid your email — this is normal for Sign in with Apple.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.85))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 8)

                        agentModeSection

                        if vaultVisible {
                            vaultDisclaimer
                            vaultPasswordsSection
                            vaultSSHSection
                        }

                        Button {
                            signingOut = true
                            dismiss()
                            Task {
                                await auth.signOut()
                                signingOut = false
                            }
                        } label: {
                            Text("Sign Out")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(WhetstoneTheme.ember.opacity(0.92))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(WhetstoneTheme.surfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(WhetstoneTheme.ember.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(signingOut)
                        .opacity(signingOut ? 0.5 : 1)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("profileSignOut")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(WhetstoneTheme.blade)
                }
            }
            .task { await loadEmail() }
            .sheet(item: $passwordEditorMode) { mode in
                VaultPasswordEditorSheet(mode: mode, store: credentialVaultStore)
                    .preferredColorScheme(.dark)
            }
            .sheet(item: $sshEditorMode) { mode in
                VaultSSHEditorSheet(mode: mode, store: credentialVaultStore)
                    .preferredColorScheme(.dark)
            }
            .confirmationDialog(
                "Delete saved password?",
                isPresented: Binding(
                    get: { deletePasswordConfirm != nil },
                    set: { if !$0 { deletePasswordConfirm = nil } }
                ),
                presenting: deletePasswordConfirm
            ) { entry in
                Button("Delete “\(entry.nickname)”", role: .destructive) {
                    credentialVaultStore.deletePassword(id: entry.id)
                    deletePasswordConfirm = nil
                }
                Button("Cancel", role: .cancel) { deletePasswordConfirm = nil }
            } message: { _ in
                Text("Removed from Keychain on this device.")
            }
            .confirmationDialog(
                "Delete SSH identity?",
                isPresented: Binding(
                    get: { deleteSSHConfirm != nil },
                    set: { if !$0 { deleteSSHConfirm = nil } }
                ),
                presenting: deleteSSHConfirm
            ) { entry in
                Button("Delete “\(entry.nickname)”", role: .destructive) {
                    credentialVaultStore.deleteSSHIdentity(id: entry.id)
                    deleteSSHConfirm = nil
                }
                Button("Cancel", role: .cancel) { deleteSSHConfirm = nil }
            } message: { _ in
                Text("Private key removed from Keychain on this device.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var agentModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent mode")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .tracking(1.4)

            HStack {
                Text(agentModeStore.mode == .advanced ? "Advanced" : "Standard")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(WhetstoneTheme.surfaceHigh.opacity(0.9))
                    )
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.95))

                Spacer()

                Toggle("", isOn: advancedToggleBinding)
                    .labelsHidden()
                    .tint(WhetstoneTheme.ember)
                    .disabled(!auth.isAdvancedUser)
            }

            if !auth.isAdvancedUser {
                Text("Advanced Mode is available to approved users.")
                    .font(.system(size: 13))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.75))
            } else {
                Text("Standard keeps the coaching mentor. Advanced unlocks network + SSH tools on-device.")
                    .font(.system(size: 13))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var vaultDisclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved credentials")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .tracking(1.4)

            Text(
                "Passwords and private keys stay on this device in Keychain. They are not synced to iCloud here and are not uploaded to Whetstone unless you enable “Allow Advanced tools”, in which case on-device SSH only may resolve them — never echoed on the transcript."
            )
            .font(.system(size: 12))
            .foregroundStyle(WhetstoneTheme.blade.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var vaultPasswordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved passwords")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Button("Add") {
                    passwordEditorMode = .add
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WhetstoneTheme.ember.opacity(0.95))
            }
            .padding(.horizontal, 24)

            if credentialVaultStore.passwords.isEmpty {
                Text("None yet — add one for SSH password auth referenced by id in Advanced mode.")
                    .font(.system(size: 13))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.72))
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(credentialVaultStore.passwords) { entry in
                        VaultPasswordRow(
                            entry: entry,
                            onEdit: { passwordEditorMode = .edit(entry) },
                            onDelete: { deletePasswordConfirm = entry },
                            onCopyPassword: { copySecretToPasteboard(kind: .password(id: entry.id)) },
                            onCopyId: { copyPlainToPasteboard(entry.id.uuidString) }
                        )
                        Divider().background(Color.white.opacity(0.12))
                    }
                }
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WhetstoneTheme.surfaceHigh.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private var vaultSSHSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SSH identities")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Button("Add") {
                    sshEditorMode = .add
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WhetstoneTheme.ember.opacity(0.95))
            }
            .padding(.horizontal, 24)

            if credentialVaultStore.sshIdentities.isEmpty {
                Text("None yet — paste an OpenSSH private key (BEGIN OPENSSH PRIVATE KEY). ECDSA keys are not supported for ssh_execute.")
                    .font(.system(size: 13))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.72))
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(credentialVaultStore.sshIdentities) { entry in
                        VaultSSHIdentityRow(
                            entry: entry,
                            onEdit: { sshEditorMode = .edit(entry) },
                            onDelete: { deleteSSHConfirm = entry },
                            onCopyId: { copyPlainToPasteboard(entry.id.uuidString) }
                        )
                        Divider().background(Color.white.opacity(0.12))
                    }
                }
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WhetstoneTheme.surfaceHigh.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private var emailDisplay: String {
        email.isEmpty ? "—" : email
    }

    private var showsApplePrivateSubtitle: Bool {
        email == "Apple account (email kept private)"
    }

    private enum PasteboardSecret {
        case password(id: UUID)
    }

    private func copySecretToPasteboard(kind: PasteboardSecret) {
        let id: UUID
        switch kind {
        case .password(let uuid): id = uuid
        }
        guard let pwd = try? credentialVaultStore.passwordSecretForClipboard(id: id) else { return }
        copySecretStringToPasteboard(pwd)
    }

    private func copyPlainToPasteboard(_ text: String) {
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(300),
        ]
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier as String: text]],
            options: options
        )
    }

    private func copySecretStringToPasteboard(_ secret: String) {
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(120),
        ]
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier as String: secret]],
            options: options
        )
    }

    private func loadEmail() async {
        guard let client = SupabaseService.shared.client else {
            await MainActor.run { email = "" }
            return
        }
        do {
            let session = try await client.auth.session
            let raw = session.user.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if let raw, !raw.isEmpty {
                    email = raw
                } else {
                    email = "Apple account (email kept private)"
                }
            }
        } catch {
            await MainActor.run { email = "" }
        }
    }
}

// MARK: - Sheet modes

private enum VaultPasswordEditorMode: Identifiable {
    case add
    case edit(VaultPasswordEntry)

    var id: String {
        switch self {
        case .add: return "vault-password-add"
        case .edit(let e): return "vault-password-\(e.id.uuidString)"
        }
    }
}

private enum VaultSSHEditorMode: Identifiable {
    case add
    case edit(VaultSSHIdentity)

    var id: String {
        switch self {
        case .add: return "vault-ssh-add"
        case .edit(let e): return "vault-ssh-\(e.id.uuidString)"
        }
    }
}

// MARK: - Rows

private struct VaultPasswordRow: View {
    let entry: VaultPasswordEntry
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onCopyPassword: () -> Void
    var onCopyId: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.nickname)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                Spacer()
                if entry.allowAgentUse {
                    Text("Agent ✓")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WhetstoneTheme.ember.opacity(0.85))
                }
            }
            Text("@\(entry.username)")
                .font(.system(size: 13))
                .foregroundStyle(WhetstoneTheme.blade.opacity(0.8))
            Text(entry.id.uuidString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(spacing: 12) {
                Button("Edit", action: onEdit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.95))
                Button("Copy password") {
                    onCopyPassword()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhetstoneTheme.blade.opacity(0.95))
                Button("Copy id", action: onCopyId)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.85))
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .padding(.top, 2)
            Text("Clipboard expires in ~2 min for pasted secrets.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct VaultSSHIdentityRow: View {
    let entry: VaultSSHIdentity
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onCopyId: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.nickname)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                Spacer()
                if entry.allowAgentUse {
                    Text("Agent ✓")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WhetstoneTheme.ember.opacity(0.85))
                }
            }

            if let u = entry.defaultUsername, !u.isEmpty {
                Text("default user: \(u)")
                    .font(.system(size: 13))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.8))
            }

            if let pk = entry.publicKeyDisplay, !pk.isEmpty {
                Text(pk)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(2)
            }

            Text(entry.id.uuidString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(spacing: 12) {
                Button("Edit", action: onEdit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.95))
                Button("Copy id", action: onCopyId)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhetstoneTheme.blade.opacity(0.85))
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Editors

private struct VaultPasswordEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: VaultPasswordEditorMode
    let store: CredentialVaultStore

    @State private var nickname: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var allowAgentUse: Bool = false
    @State private var comment: String = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if case .edit = mode {
                    Section {
                        Text("Leave password empty to keep the current secret.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Entry") {
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                    TextField("SSH username hint", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField(mode.isAdd ? "Password" : "Password (optional)", text: $password)
                    Toggle("Allow Advanced tools", isOn: $allowAgentUse)
                }

                Section {
                    Text("When off, saved_password_id lookups fail tools with a permission error.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("Comment (optional)", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.isAdd ? "Add password" : "Edit password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                }
            }
            .onAppear { prime() }
        }
    }

    private func prime() {
        switch mode {
        case .add:
            nickname = ""
            username = ""
            password = ""
            allowAgentUse = false
            comment = ""
        case .edit(let e):
            nickname = e.nickname
            username = e.username
            password = ""
            allowAgentUse = e.allowAgentUse
            comment = e.comment ?? ""
        }
        errorText = nil
    }

    private func save() {
        do {
            switch mode {
            case .add:
                try store.upsertPassword(
                    nickname: nickname,
                    username: username,
                    passwordPlain: password,
                    allowAgentUse: allowAgentUse,
                    comment: comment
                )
            case .edit(let e):
                try store.upsertPassword(
                    id: e.id,
                    nickname: nickname,
                    username: username,
                    passwordPlain: password.isEmpty ? nil : password,
                    allowAgentUse: allowAgentUse,
                    comment: comment
                )
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct VaultSSHEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: VaultSSHEditorMode
    let store: CredentialVaultStore

    @State private var nickname: String = ""
    @State private var defaultUsername: String = ""
    @State private var privateKey: String = ""
    @State private var allowAgentUse: Bool = false
    @State private var publicKeyDisplay: String = ""
    @State private var comment: String = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if case .edit = mode {
                    Section {
                        Text("Leave private key empty to keep the current key.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Identity") {
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                    TextField("Default SSH username (optional)", text: $defaultUsername)
                        .textInputAutocapitalization(.never)

                    Toggle("Allow Advanced tools", isOn: $allowAgentUse)
                }

                Section("Private key (OpenSSH)") {
                    TextEditor(text: $privateKey)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: mode.isAdd ? 120 : 80)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Section("Public key (display only)") {
                    TextField("Paste `ssh-ed25519` / `ssh-rsa` line (optional)", text: $publicKeyDisplay, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(3...8)
                }

                Section {
                    Text("Private key never appears in chat history. ECDSA PEM is not wired for ssh_execute.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("Comment (optional)", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.isAdd ? "Add SSH identity" : "Edit SSH identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                }
            }
            .onAppear { prime() }
        }
    }

    private func prime() {
        switch mode {
        case .add:
            nickname = ""
            defaultUsername = ""
            privateKey = ""
            allowAgentUse = false
            publicKeyDisplay = ""
            comment = ""
        case .edit(let e):
            nickname = e.nickname
            defaultUsername = e.defaultUsername ?? ""
            privateKey = ""
            allowAgentUse = e.allowAgentUse
            publicKeyDisplay = e.publicKeyDisplay ?? ""
            comment = e.comment ?? ""
        }
        errorText = nil
    }

    private func save() {
        do {
            let duTrim = defaultUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultUserOpt = duTrim.isEmpty ? nil : duTrim

            switch mode {
            case .add:
                try store.upsertSSHIdentity(
                    nickname: nickname,
                    defaultUsername: defaultUserOpt,
                    privateKeyPEM: privateKey,
                    allowAgentUse: allowAgentUse,
                    publicKeyDisplay: publicKeyDisplay,
                    comment: comment
                )
            case .edit(let e):
                try store.upsertSSHIdentity(
                    id: e.id,
                    nickname: nickname,
                    defaultUsername: defaultUserOpt,
                    privateKeyPEM: privateKey.isEmpty ? nil : privateKey,
                    allowAgentUse: allowAgentUse,
                    publicKeyDisplay: publicKeyDisplay,
                    comment: comment
                )
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private extension VaultPasswordEditorMode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

private extension VaultSSHEditorMode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
        .environmentObject(AgentModeStore())
        .environmentObject(CredentialVaultStore())
}
