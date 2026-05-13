import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ZStack {
            WhetstoneTheme.obsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: Wordmark
                VStack(spacing: 20) {
                    BladeMarkView()

                    Text("WHETSTONE")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .tracking(8)
                        .foregroundColor(.white)

                    Text("Sharpen your craft.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(WhetstoneTheme.blade.opacity(0.85))
                        .tracking(1)
                }

                // MARK: Features
                VStack(spacing: 0) {
                    Text("Your personal mentor for drawing, writing, music, repair, and more — built to sharpen real skill, not shortcut it.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 36)
                        .padding(.top, 28)
                        .padding(.bottom, 32)

                    VStack(spacing: 0) {
                        FeatureRow(
                            icon: "camera.viewfinder",
                            title: "Vision-first feedback",
                            detail: "Attach photos and get critique on what you actually made."
                        )
                        Divider()
                            .background(Color.white.opacity(0.07))
                        FeatureRow(
                            icon: "figure.mind.and.body",
                            title: "Coaching, not shortcuts",
                            detail: "The mentor asks questions and holds you to the work."
                        )
                        Divider()
                            .background(Color.white.opacity(0.07))
                        FeatureRow(
                            icon: "square.stack.3d.up",
                            title: "Every craft, one app",
                            detail: "Drawing, writing, music, repair, study, and more."
                        )
                    }
                    .background(WhetstoneTheme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }

                Spacer()

                // MARK: Sign in
                VStack(spacing: 16) {
                    if !WhetstoneConstants.isSupabaseConfigured {
                        MissingKeysCallout()
                    }

                    SignInWithAppleButton(.signIn, onRequest: { request in
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = auth.prepareAppleNonce()
                    }, onCompletion: { result in
                        Task { await auth.handleAppleSignIn(result) }
                    })
                    .signInWithAppleButtonStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .disabled(!WhetstoneConstants.isSupabaseConfigured || auth.isLoading)
                    .opacity(WhetstoneConstants.isSupabaseConfigured ? 1 : 0.4)

                    if auth.isLoading {
                        ProgressView()
                            .tint(WhetstoneTheme.blade)
                    }

                    if let msg = auth.errorMessage {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundColor(WhetstoneTheme.ember)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - Blade mark (geometric whetstone icon)

private struct BladeMarkView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WhetstoneTheme.surfaceHigh)
                .frame(width: 72, height: 72)

            // A chamfered diamond as the whetstone glyph
            Diamond()
                .fill(WhetstoneTheme.blade)
                .frame(width: 30, height: 36)

            Diamond()
                .stroke(WhetstoneTheme.blade.opacity(0.3), lineWidth: 1.5)
                .frame(width: 38, height: 46)
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to:    CGPoint(x: rect.midX,  y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX,  y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX,  y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX,  y: rect.midY))
            p.closeSubpath()
        }
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(WhetstoneTheme.blade)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Missing keys callout

private struct MissingKeysCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundColor(WhetstoneTheme.ember)
                .padding(.top, 1)
            Text("Supabase keys are missing. Add `SupabaseURL` and `SupabaseAnonKey` to **Info.plist**, then clean and rebuild.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhetstoneTheme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WhetstoneTheme.ember.opacity(0.4), lineWidth: 1)
        )
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
