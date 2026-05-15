import SwiftUI
import Supabase

/// Account sheet — sign out. Email from current Supabase session.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var agentModeStore: AgentModeStore

    @State private var email: String = ""
    @State private var signingOut = false

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

                    Spacer(minLength: 20)

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
                    .padding(.bottom, 24)
                    .accessibilityIdentifier("profileSignOut")
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
        }
        .preferredColorScheme(.dark)
    }

    private var emailDisplay: String {
        email.isEmpty ? "—" : email
    }

    private var showsApplePrivateSubtitle: Bool {
        email == "Apple account (email kept private)"
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

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
        .environmentObject(AgentModeStore())
}
