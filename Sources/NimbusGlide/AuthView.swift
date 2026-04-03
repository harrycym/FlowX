import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var otpCode = ""
    @State private var showEmailForm = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Logo + branding
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(NimbusGradients.subtle)
                            .frame(width: 80, height: 80)
                        Image(systemName: "waveform")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(NimbusGradients.primary)
                    }

                    Text("NimbusGlide")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(NimbusColors.heading)

                    if authManager.emailAuthState == .needsVerification {
                        Text("Check your email for a verification code.")
                            .font(NimbusFonts.body)
                            .foregroundColor(NimbusColors.muted)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("AI dictation that thinks.\nSpeak naturally, get polished text.")
                            .font(NimbusFonts.body)
                            .foregroundColor(NimbusColors.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                }

                if authManager.emailAuthState == .needsVerification {
                    // OTP Verification screen
                    VStack(spacing: 14) {
                        Text("We sent a 6-digit code to")
                            .font(NimbusFonts.body)
                            .foregroundColor(NimbusColors.muted)
                        Text(email)
                            .font(NimbusFonts.bodyMedium)

                        TextField("Enter code", text: $otpCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .multilineTextAlignment(.center)
                            .font(.title2.weight(.medium).monospacedDigit())
                            .onSubmit { authManager.verifyEmailOTP(otpCode) }

                        Button(action: { authManager.verifyEmailOTP(otpCode) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Verify")
                                    .font(NimbusFonts.bodyMedium)
                            }
                            .frame(maxWidth: 300)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(otpCode.isEmpty)

                        Button("Back") {
                            authManager.emailAuthState = .enterCredentials
                            authManager.errorMessage = nil
                            otpCode = ""
                        }
                        .font(NimbusFonts.caption)
                        .foregroundColor(NimbusColors.indigo)
                    }
                    .disabled(authManager.isLoading)
                } else {
                    // Main auth screen
                    VStack(spacing: 12) {
                        // Google Sign-In
                        Button(action: { authManager.signIn(provider: .google) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                Text("Continue with Google")
                                    .font(NimbusFonts.bodyMedium)
                            }
                            .frame(maxWidth: 300)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle().fill(NimbusColors.muted.opacity(0.15)).frame(height: 1)
                            Text("or")
                                .font(NimbusFonts.caption)
                                .foregroundColor(NimbusColors.muted.opacity(0.7))
                            Rectangle().fill(NimbusColors.muted.opacity(0.15)).frame(height: 1)
                        }
                        .frame(maxWidth: 300)

                        if showEmailForm {
                            VStack(spacing: 10) {
                                TextField("Email address", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 300)

                                SecureField("Password (min 6 characters)", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 300)
                                    .onSubmit { authManager.signInWithEmail(email, password: password) }

                                Button(action: { authManager.signInWithEmail(email, password: password) }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.right.circle.fill")
                                        Text("Sign In / Sign Up")
                                            .font(NimbusFonts.bodyMedium)
                                    }
                                    .frame(maxWidth: 300)
                                    .padding(.vertical, 11)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .disabled(email.isEmpty || password.count < 6)

                                Text("New? Enter email + password to create an account.\nExisting? Just sign in.")
                                    .font(NimbusFonts.small)
                                    .foregroundColor(NimbusColors.muted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 280)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showEmailForm = true } }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope")
                                    Text("Continue with Email")
                                        .font(NimbusFonts.bodyMedium)
                                }
                                .frame(maxWidth: 300)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                    .disabled(authManager.isLoading)
                }

                if authManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if let error = authManager.errorMessage {
                    Text(error)
                        .font(NimbusFonts.caption)
                        .foregroundColor(NimbusColors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text("Free to start")
                    .font(NimbusFonts.small)
                    .foregroundColor(NimbusColors.muted)
                Circle().fill(NimbusColors.muted.opacity(0.3)).frame(width: 3, height: 3)
                Text("2,000 words/month")
                    .font(NimbusFonts.small)
                    .foregroundColor(NimbusColors.muted)
                Circle().fill(NimbusColors.muted.opacity(0.3)).frame(width: 3, height: 3)
                Text("Pro from $3/mo")
                    .font(NimbusFonts.small)
                    .foregroundColor(NimbusColors.muted)
            }
            .padding(.bottom, 16)
        }
        .frame(width: NimbusLayout.sheetWidth, height: 540)
    }
}
