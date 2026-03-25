import Foundation

class AIService {
    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    // MARK: - Groq Whisper Transcription

    func transcribeAudio(fileURL: URL) async throws -> String {
        guard let apiKey = settingsManager.apiKey, !apiKey.isEmpty else {
            throw FlowXError.noAPIKey
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let audioData = try Data(contentsOf: fileURL)

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-large-v3")
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        body.appendMultipartFile(boundary: boundary, name: "file", filename: fileURL.lastPathComponent, mimeType: "audio/wav", data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlowXError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FlowXError.apiError("Groq Whisper error (\(httpResponse.statusCode)): \(errorBody)")
        }

        let transcript = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return transcript
    }

    // MARK: - Groq LLM Processing

    func processWithLLM(
        transcript: String,
        activeApp: String,
        profileInstructions: String?,
        memoryExamples: [MemoryEntry]
    ) async throws -> String {
        guard let apiKey = settingsManager.apiKey, !apiKey.isEmpty else {
            throw FlowXError.noAPIKey
        }

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

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FlowXError.apiError("Groq LLM error: \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw FlowXError.apiError("Failed to parse Groq response")
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard against the model going into chatbot mode — if the output is
        // drastically longer than the input and contains telltale phrases, discard it
        let chatbotPhrases = ["I'm here to help", "I don't have the capability", "text-based", "How can I", "What can I", "I'm a"]
        if case .noCommand = parsed {
            let isChatbotResponse = chatbotPhrases.contains(where: { result.localizedCaseInsensitiveContains($0) })
            if isChatbotResponse {
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

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

// MARK: - Errors

enum FlowXError: LocalizedError {
    case noAPIKey
    case networkError(String)
    case apiError(String)
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Groq API key configured. Please set it in Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let msg):
            return msg
        case .recordingFailed:
            return "Failed to record audio."
        }
    }
}
