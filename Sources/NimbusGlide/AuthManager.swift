import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

enum AuthProvider: String {
    case google
    case apple
}

struct NimbusUser {
    let id: String
    let email: String
    let displayName: String?
    let avatarURL: String?
}

class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: NimbusUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabaseURL: String
    private let supabaseAnonKey: String

    // PKCE state
    private var codeVerifier: String?

    // Token keys
    private static let accessTokenKey = "nimbusglide_access_token"
    private static let refreshTokenKey = "nimbusglide_refresh_token"

    override init() {
        // Load Supabase config from bundled Secrets.plist
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            self.supabaseURL = dict["SupabaseURL"] as? String ?? ""
            self.supabaseAnonKey = dict["SupabaseAnonKey"] as? String ?? ""
        } else {
            self.supabaseURL = ""
            self.supabaseAnonKey = ""
        }
        super.init()
    }

    var hasValidConfig: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty && supabaseURL.hasPrefix("https://")
    }

    // MARK: - Session Restore

    func restoreSession() {
        guard let accessToken = KeychainHelper.load(key: Self.accessTokenKey),
              let refreshToken = KeychainHelper.load(key: Self.refreshTokenKey) else {
            return
        }

        // Try to use the existing token — refresh if needed
        isLoading = true
        Task {
            do {
                let token = try await refreshTokenIfNeeded(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
                let user = try await fetchUser(accessToken: token)
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            } catch {
                // Tokens are invalid — clear them
                await MainActor.run {
                    self.clearSession()
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Email + Password Auth

    /// Tracks email auth flow state
    @Published var emailAuthState: EmailAuthState = .enterCredentials
    private var pendingEmail: String = ""
    private var pendingPassword: String = ""

    enum EmailAuthState {
        case enterCredentials
        case needsVerification  // signup succeeded, waiting for OTP code
    }

    func signInWithEmail(_ email: String, password: String) {
        guard hasValidConfig else {
            errorMessage = "App not configured. Please reinstall."
            return
        }
        guard !email.isEmpty, email.contains("@") else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        errorMessage = nil
        pendingEmail = email
        pendingPassword = password

        Task {
            do {
                // Try sign in first (existing user)
                let signInResult = try? await emailSignIn(email: email, password: password)

                if let tokens = signInResult {
                    KeychainHelper.save(key: Self.accessTokenKey, value: tokens.accessToken)
                    KeychainHelper.save(key: Self.refreshTokenKey, value: tokens.refreshToken)
                    let user = try await fetchUser(accessToken: tokens.accessToken)
                    await MainActor.run {
                        self.currentUser = user
                        self.isAuthenticated = true
                        self.isLoading = false
                        self.clearPendingCredentials()
                    }
                    return
                }

                // Sign in failed — try sign up (new user)
                let signUpTokens = try await emailSignUp(email: email, password: password)

                if let tokens = signUpTokens {
                    // Email confirmation disabled — signed up and logged in immediately
                    KeychainHelper.save(key: Self.accessTokenKey, value: tokens.accessToken)
                    KeychainHelper.save(key: Self.refreshTokenKey, value: tokens.refreshToken)
                    let user = try await fetchUser(accessToken: tokens.accessToken)
                    await MainActor.run {
                        self.currentUser = user
                        self.isAuthenticated = true
                        self.isLoading = false
                        self.clearPendingCredentials()
                    }
                } else {
                    // nil = confirmation email sent, OTP screen already set inside emailSignUp
                    // Keep pendingEmail/pendingPassword for OTP verification flow
                    await MainActor.run { self.isLoading = false }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.clearPendingCredentials()
                }
            }
        }
    }

    /// Verify the OTP code sent to the user's email after signup
    func verifyEmailOTP(_ code: String) {
        guard !code.isEmpty else {
            errorMessage = "Please enter the verification code."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/verify")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "type": "signup",
                    "email": pendingEmail,
                    "token": code.trimmingCharacters(in: .whitespacesAndNewlines)
                ])

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.isLoading = false
                        if body.contains("expired") {
                            self.errorMessage = "Code expired. Please sign up again."
                        } else {
                            self.errorMessage = "Invalid verification code."
                        }
                    }
                    return
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let accessToken = json["access_token"] as? String,
                      let refreshToken = json["refresh_token"] as? String else {
                    // Verification succeeded but no tokens — sign in with credentials
                    let tokens = try await emailSignIn(email: pendingEmail, password: pendingPassword)
                    KeychainHelper.save(key: Self.accessTokenKey, value: tokens.accessToken)
                    KeychainHelper.save(key: Self.refreshTokenKey, value: tokens.refreshToken)
                    let user = try await fetchUser(accessToken: tokens.accessToken)
                    await MainActor.run {
                        self.currentUser = user
                        self.isAuthenticated = true
                        self.isLoading = false
                        self.emailAuthState = .enterCredentials
                        self.clearPendingCredentials()
                    }
                    return
                }

                KeychainHelper.save(key: Self.accessTokenKey, value: accessToken)
                KeychainHelper.save(key: Self.refreshTokenKey, value: refreshToken)
                let user = try await fetchUser(accessToken: accessToken)
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.isLoading = false
                    self.emailAuthState = .enterCredentials
                    self.clearPendingCredentials()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.clearPendingCredentials()
                }
            }
        }
    }

    private func emailSignIn(email: String, password: String) async throws -> TokenPair {
        var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed("Invalid credentials")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw AuthError.tokenExchangeFailed("Invalid response from server.")
        }

        return TokenPair(accessToken: accessToken, refreshToken: refreshToken)
    }

    /// Returns tokens if email confirmation is disabled (immediate login),
    /// or nil + sets needsVerification state if confirmation email was sent.
    /// Throws if the user already exists (wrong password scenario).
    private func emailSignUp(email: String, password: String) async throws -> TokenPair? {
        var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/signup")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResp = response as? HTTPURLResponse

        if httpResp?.statusCode == 200 {
            // If Supabase returns tokens, email confirmation is disabled — log in immediately
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String,
               let refreshToken = json["refresh_token"] as? String {
                return TokenPair(accessToken: accessToken, refreshToken: refreshToken)
            }
            // No tokens = confirmation email sent, OTP required
            await MainActor.run { self.emailAuthState = .needsVerification }
            return nil
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        if body.contains("already registered") || httpResp?.statusCode == 422 {
            throw AuthError.tokenExchangeFailed("Incorrect password for this email.")
        }

        throw AuthError.tokenExchangeFailed("Sign up failed. Please try again.")
    }

    // MARK: - OAuth Sign In

    func signIn(provider: AuthProvider) {
        guard hasValidConfig else {
            errorMessage = "App not configured. Please reinstall."
            return
        }

        isLoading = true
        errorMessage = nil

        // Generate PKCE code verifier + challenge
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        // Build authorization URL
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: "nimbusglide://auth/callback"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "flow_type", value: "pkce"),
        ]

        guard let url = components.url else {
            errorMessage = "Failed to build auth URL"
            isLoading = false
            return
        }

        // Open ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "nimbusglide"
        ) { [weak self] callbackURL, error in
            guard let self else { return }

            DispatchQueue.main.async {
                if let error {
                    // User cancelled or error
                    if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isLoading = false
                    return
                }

                guard let callbackURL else {
                    self.errorMessage = "No callback received"
                    self.isLoading = false
                    return
                }

                self.handleCallback(url: callbackURL)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        session.start()
    }

    // MARK: - OAuth Callback

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            errorMessage = "Invalid callback URL"
            isLoading = false
            return
        }

        // Supabase may return code in query params OR in the fragment
        let code: String? = components.queryItems?.first(where: { $0.name == "code" })?.value
            ?? parseFragment(components.fragment)?["code"]

        guard let code, let verifier = codeVerifier else {
            errorMessage = "Invalid callback: no auth code received"
            isLoading = false
            return
        }

        self.codeVerifier = nil

        // Exchange code for tokens
        Task {
            do {
                let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: verifier)

                // Store tokens in Keychain
                KeychainHelper.save(key: Self.accessTokenKey, value: tokens.accessToken)
                KeychainHelper.save(key: Self.refreshTokenKey, value: tokens.refreshToken)

                // Fetch user info
                let user = try await fetchUser(accessToken: tokens.accessToken)

                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        // Revoke on server (best-effort)
        if let accessToken = KeychainHelper.load(key: Self.accessTokenKey) {
            Task {
                var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/logout")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        clearSession()
    }

    private func clearSession() {
        KeychainHelper.delete(key: Self.accessTokenKey)
        KeychainHelper.delete(key: Self.refreshTokenKey)
        isAuthenticated = false
        currentUser = nil
        clearPendingCredentials()
    }

    private func clearPendingCredentials() {
        pendingEmail = ""
        pendingPassword = ""
    }

    // MARK: - Token Management

    /// Returns a valid access token, refreshing if needed.
    func validAccessToken() async throws -> String {
        guard let accessToken = KeychainHelper.load(key: Self.accessTokenKey),
              let refreshToken = KeychainHelper.load(key: Self.refreshTokenKey) else {
            throw AuthError.notAuthenticated
        }

        return try await refreshTokenIfNeeded(accessToken: accessToken, refreshToken: refreshToken)
    }

    private func refreshTokenIfNeeded(accessToken: String, refreshToken: String) async throws -> String {
        // Check if token is expired by decoding JWT payload
        if !isTokenExpired(accessToken) {
            return accessToken
        }

        // Token expired — refresh it
        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "refresh_token": refreshToken
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String,
              let newRefresh = json["refresh_token"] as? String else {
            throw AuthError.tokenRefreshFailed
        }

        KeychainHelper.save(key: Self.accessTokenKey, value: newAccess)
        KeychainHelper.save(key: Self.refreshTokenKey, value: newRefresh)

        return newAccess
    }

    private func isTokenExpired(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }

        var payload = String(parts[1])
        // Pad base64
        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }

        // Consider expired if within 60 seconds of expiry
        return Date().timeIntervalSince1970 >= (exp - 60)
    }

    /// Parse URL fragment like "code=abc&other=def" into a dictionary
    private func parseFragment(_ fragment: String?) -> [String: String]? {
        guard let fragment, !fragment.isEmpty else { return nil }
        var result: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let val = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                result[key] = val
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - API Calls

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> TokenPair {
        var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/token?grant_type=pkce")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "auth_code": code,
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw AuthError.tokenExchangeFailed("Invalid response")
        }

        return TokenPair(accessToken: accessToken, refreshToken: refreshToken)
    }

    private func fetchUser(accessToken: String) async throws -> NimbusUser {
        var request = URLRequest(url: URL(string: "\(supabaseURL)/auth/v1/user")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AuthError.notAuthenticated
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.notAuthenticated
        }

        let id = json["id"] as? String ?? ""
        let email = json["email"] as? String ?? ""
        let meta = json["user_metadata"] as? [String: Any]
        let displayName = meta?["full_name"] as? String ?? meta?["name"] as? String
        let avatarURL = meta?["avatar_url"] as? String

        return NimbusUser(id: id, email: email, displayName: displayName, avatarURL: avatarURL)
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApp.windows.first { $0.isKeyWindow } ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Supporting Types

private struct TokenPair {
    let accessToken: String
    let refreshToken: String
}

enum AuthError: LocalizedError {
    case notAuthenticated
    case tokenRefreshFailed
    case tokenExchangeFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in. Please sign in to continue."
        case .tokenRefreshFailed:
            return "Session expired. Please sign in again."
        case .tokenExchangeFailed(let detail):
            return "Sign-in failed: \(detail)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}
