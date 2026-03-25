import Foundation

struct WakewordParser {
    static let wakeword = "nimbus glide"

    // Fuzzy matching: Whisper often mistranscribes "Nimbus Glide" as similar-sounding words.
    // Match "nimbus" (or phonetic variants) + separator + "glide" (or phonetic variants).
    private static let nimbusVariants = [
        "nimbus", "nimbis", "nimbes", "nimba", "nimbas", "nimbus's", "nimbus'",
    ]
    private static let glideVariants = [
        "glide", "guide", "blood", "flood", "slide", "glade", "glyde", "glied",
        "glad", "cloud", "clide", "clyde", "glined", "glowed", "slied", "glite",
        "gloid", "blude", "blide", "glood",
    ]
    // Separators between the two words (space, comma, hyphen, period, or nothing)
    private static let separatorPattern = "[\\s,\\-\\.]*"

    private static var wakewordRegex: NSRegularExpression = {
        let nimbusGroup = nimbusVariants.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let glideGroup = glideVariants.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "(?:\(nimbusGroup))\(separatorPattern)(?:\(glideGroup))"
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    enum ParseResult {
        case withCommand(content: String, command: String)
        case noCommand(content: String)
    }

    /// Parses a transcript for the "nimbus glide" wakeword (with fuzzy phonetic matching).
    /// If found, splits into content (before) and command (after).
    /// If not found, returns the whole text as content with no command.
    static func parse(_ transcript: String) -> ParseResult {
        let nsRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)

        guard let match = wakewordRegex.firstMatch(in: transcript, range: nsRange),
              let matchRange = Range(match.range, in: transcript) else {
            return .noCommand(content: transcript)
        }

        let contentEnd = transcript[transcript.startIndex..<matchRange.lowerBound]
        let commandStart = transcript[matchRange.upperBound..<transcript.endIndex]

        let content = String(contentEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        let command = String(commandStart).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[,.\\s]+", with: "", options: .regularExpression)

        if !content.isEmpty && !command.isEmpty {
            return .withCommand(content: content, command: command)
        } else if !content.isEmpty {
            return .noCommand(content: content)
        } else if !command.isEmpty {
            return .withCommand(content: "", command: command)
        }

        return .noCommand(content: transcript)
    }
}
