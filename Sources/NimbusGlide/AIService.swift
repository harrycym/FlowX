import Foundation

class AIService {
    private let settingsManager: SettingsManager
    private let authManager: AuthManager
    var usageTracker: UsageTracker?

    /// Cloudflare Worker URL — loaded from Secrets.plist via APIClient
    private let workerURL: String

    init(settingsManager: SettingsManager, apiClient: APIClient) {
        self.settingsManager = settingsManager
        self.authManager = apiClient.authManager
        self.workerURL = apiClient.workerURL
    }

    // MARK: - Transcription (via Cloudflare Worker)

    func transcribeAudio(fileURL: URL) async throws -> String {
        let token = try await authManager.validAccessToken()

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(workerURL)/transcribe")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "file", filename: fileURL.lastPathComponent, mimeType: "audio/wav", data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResp = response as? HTTPURLResponse

        if httpResp?.statusCode == 403 {
            throw NimbusGlideError.usageLimitReached
        }

        guard httpResp?.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NimbusGlideError.apiError("Transcription error: \(errBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcript = json["transcript"] as? String else {
            throw NimbusGlideError.apiError("Invalid transcription response")
        }

        return transcript
    }

    // MARK: - LLM Processing (via Cloudflare Worker)

    func processWithLLM(
        transcript: String,
        activeApp: String,
        profileInstructions: String?,
        memoryExamples: [MemoryEntry]
    ) async throws -> String {
        let token = try await authManager.validAccessToken()

        let parsed = WakewordParser.parse(transcript)
        let systemPrompt = buildSystemPrompt(
            parsed: parsed,
            activeApp: activeApp,
            profileInstructions: profileInstructions,
            memoryExamples: memoryExamples
        )

        let userContent: String
        switch parsed {
        case .withCommand(let content, let command):
            userContent = "Content to Edit:\n\"\(content)\"\n\nCommand:\n\"\(command)\"\n\nOUTPUT ONLY THE EDITED TEXT:"
        case .noCommand(let content):
            userContent = "Raw Audio Transcript:\n\"\(content)\"\n\nOUTPUT ONLY THE CLEANED TEXT:"
        }

        let payload: [String: Any] = [
            "model": settingsManager.llmModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.0,
            "max_tokens": 2048
        ]

        var request = URLRequest(url: URL(string: "\(workerURL)/process")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NimbusGlideError.apiError("Processing error: \(errBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw NimbusGlideError.apiError("Invalid processing response")
        }

        // Update local usage counter from worker response
        if let words = json["words"] as? Int, let tracker = usageTracker {
            await MainActor.run {
                tracker.totalWordsUsed += words
            }
        }

        // Guard against chatbot mode
        let chatbotPhrases = ["I'm here to help", "I don't have the capability", "text-based", "How can I", "What can I", "I'm a"]
        if case .noCommand = parsed {
            if chatbotPhrases.contains(where: { result.localizedCaseInsensitiveContains($0) }) {
                return transcript
            }
        }

        return result
    }

    // MARK: - System Prompt Builder

    private func buildSystemPrompt(
        parsed: WakewordParser.ParseResult,
        activeApp: String,
        profileInstructions: String?,
        memoryExamples: [MemoryEntry]
    ) -> String {
        var prompt = ""

        switch parsed {
        case .withCommand:
            prompt += "You are a direct formatting engine. The user will provide Content and a Command. Apply the Command to the Content. "
            prompt += "CRITICAL: Return ONLY the final edited text. NEVER output explanations, markdown, or conversational phrases like 'Here is the edited text'. "
            prompt += "The text is being injected directly into '\(activeApp)'."
        case .noCommand:
            prompt += """
            You are an expert transcription copyeditor.
            Your task is to take a raw, messy speech-to-text audio transcript and rewrite it into flawlessly flowing, grammatically correct text.

            CRITICAL RULES:
            1. FIX MISTAKES: Resolve all stutters, mid-sentence self-corrections, and restarts smoothly.
               - Example Input: "I went to the beach, actually no, I'm going to the mall."
               - Example Output: "I'm going to the mall."
            2. ADD PUNCTUATION: Add commas, periods, and capitalization to make the text read naturally.
            3. REMOVE FILLER: Only strip meaningless verbal tics like "um", "uh", "ah", "er", and repeated stuttered words. Do NOT remove words that carry meaning or tone like "honestly", "actually", "basically", "literally", "seriously" — those are intentional.
            4. KEEP ORIGINAL INTENT: Never answer questions asked in the transcript. Just transcribe the question perfectly.
            5. NO CHATBOT BEHAVIOR: You are a silent backend engine. NEVER output conversational prefixes like "Here is your text" or "Sure". ONLY output the finalized, flowing text.
            6. PRESERVE AUTHENTIC VOICE: NEVER sanitize, soften, or remove expletives, slang, or emotional language. If the speaker says "fucking", output "fucking". Preserve the speaker's raw personality exactly as spoken. Do NOT substitute or censor any words.

            The final text is being injected directly into '\(activeApp)'.
            """
        }

        if let profileInstructions, !profileInstructions.isEmpty {
            prompt += "\n\nCRITICAL TONE DIRECTIVE:\nYou MUST format the transcript strictly according to this active profile rule: '\(profileInstructions)'. If this rule conflicts with the raw transcript structure, the rule wins."
        }

        if !memoryExamples.isEmpty {
            prompt += "\n\nHere are examples of how the user prefers their text to be formatted (learn from these):"
            for (i, entry) in memoryExamples.prefix(5).enumerated() {
                prompt += "\n\nExample \(i + 1):"
                prompt += "\nInput: \(entry.rawTranscript)"
                prompt += "\nOutput: \(entry.polishedText)"
            }
        }

        return prompt
    }
}

// MARK: - Multipart Helper

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

// MARK: - Errors

enum NimbusGlideError: LocalizedError, Equatable {
    static func == (lhs: NimbusGlideError, rhs: NimbusGlideError) -> Bool {
        switch (lhs, rhs) {
        case (.noAPIKey, .noAPIKey), (.notAuthenticated, .notAuthenticated),
             (.recordingFailed, .recordingFailed), (.usageLimitReached, .usageLimitReached):
            return true
        case (.networkError(let a), .networkError(let b)), (.apiError(let a), .apiError(let b)):
            return a == b
        default:
            return false
        }
    }

    case noAPIKey
    case notAuthenticated
    case networkError(String)
    case apiError(String)
    case recordingFailed
    case usageLimitReached

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "NimbusGlide is not configured correctly. Please reinstall."
        case .notAuthenticated:
            return "Please sign in to use NimbusGlide."
        case .networkError(let msg):
            return "Connection issue: \(msg)"
        case .apiError(let msg):
            return msg
        case .recordingFailed:
            return "Couldn't access your microphone. Check permissions."
        case .usageLimitReached:
            return "You've used all your free words. Upgrade to keep speaking."
        }
    }
}
