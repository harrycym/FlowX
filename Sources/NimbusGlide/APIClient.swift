import Foundation

struct UserStatus {
    let userId: String
    let email: String
    let displayName: String?
    let avatarURL: String?
    let plan: String
    let wordsUsed: Int
    let wordLimit: Int?
    let subscriptionStatus: String
    let currentPeriodEnd: String?
}

struct ProcessResult {
    let text: String
    let wordsUsed: Int
    let wordLimit: Int?
    let wordsRemaining: Int?
}

class APIClient {
    let authManager: AuthManager
    private let supabaseURL: String

    /// Cloudflare Worker URL — loaded from Secrets.plist
    let workerURL: String

    init(authManager: AuthManager) {
        self.authManager = authManager

        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            self.supabaseURL = dict["SupabaseURL"] as? String ?? ""
            self.workerURL = dict["WorkerURL"] as? String ?? ""
        } else {
            self.supabaseURL = ""
            self.workerURL = ""
        }
    }

    // MARK: - User Status (via Cloudflare Worker)

    func getUserStatus() async throws -> UserStatus {
        let (data, _) = try await authenticatedRequest(
            url: "\(workerURL)/user-status",
            method: "GET"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIClientError.invalidResponse
        }

        return UserStatus(
            userId: json["user_id"] as? String ?? "",
            email: json["email"] as? String ?? "",
            displayName: json["display_name"] as? String,
            avatarURL: json["avatar_url"] as? String,
            plan: json["plan"] as? String ?? "free",
            wordsUsed: json["words_used"] as? Int ?? 0,
            wordLimit: json["word_limit"] as? Int,
            subscriptionStatus: json["subscription_status"] as? String ?? "active",
            currentPeriodEnd: json["current_period_end"] as? String
        )
    }

    // MARK: - Stripe Checkout (via Cloudflare Worker)

    func createCheckoutSession(priceId: String? = nil) async throws -> URL {
        var body: [String: Any] = [:]
        if let priceId { body["price_id"] = priceId }

        let (data, response) = try await authenticatedJSONRequest(
            url: "\(workerURL)/create-checkout",
            method: "POST",
            body: body
        )

        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = json["checkout_url"] as? String,
              let url = URL(string: urlString) else {
            throw APIClientError.invalidResponse
        }

        return url
    }

    // MARK: - Authenticated Request Helpers

    private func authenticatedRequest(url: String, method: String) async throws -> (Data, URLResponse) {
        let token = try await authManager.validAccessToken()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let newToken = try await authManager.validAccessToken()
            var retryReq = request
            retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await URLSession.shared.data(for: retryReq)
        }

        return (data, response)
    }

    private func authenticatedJSONRequest(url: String, method: String, body: [String: Any]) async throws -> (Data, URLResponse) {
        let token = try await authManager.validAccessToken()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let newToken = try await authManager.validAccessToken()
            var retryReq = request
            retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await URLSession.shared.data(for: retryReq)
        }

        return (data, response)
    }
}

enum APIClientError: LocalizedError {
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .notConfigured: return "Backend not configured"
        }
    }
}
