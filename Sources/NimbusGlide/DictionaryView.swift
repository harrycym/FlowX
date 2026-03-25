import SwiftUI

struct DictionaryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var wrong: String
    var correct: String
}

class DictionaryManager: ObservableObject {
    private static let storageKey = "nimbusglide_dictionary"

    @Published var entries: [DictionaryEntry] {
        didSet { save() }
    }

    private static let defaultEntries: [DictionaryEntry] = [
        DictionaryEntry(wrong: "chat gpt", correct: "ChatGPT"),
        DictionaryEntry(wrong: "iphone", correct: "iPhone"),
        DictionaryEntry(wrong: "linkedin", correct: "LinkedIn"),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = Self.defaultEntries
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func add(wrong: String, correct: String) {
        entries.insert(DictionaryEntry(wrong: wrong, correct: correct), at: 0)
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    /// Applies all dictionary corrections to the text.
    /// Case-insensitive word boundary matching.
    func applyCorrections(_ text: String) -> String {
        var result = text
        for entry in entries {
            // Use word boundary regex for accurate replacement
            if let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: entry.wrong))\\b",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: entry.correct
                )
            }
        }
        return result
    }
}

struct DictionaryView: View {
    @EnvironmentObject var dictionaryManager: DictionaryManager
    @State private var newWrong = ""
    @State private var newCorrect = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Dictionary")
                    .font(.title2.weight(.bold))
                    .foregroundColor(NimbusColors.heading)
                Text("Add words and phrases that NimbusGlide frequently gets wrong. These corrections are applied automatically after every dictation.")
                    .font(.caption)
                    .foregroundColor(NimbusColors.muted)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NimbusLayout.contentPadding)

            Divider()

            // Add new entry
            HStack(spacing: 12) {
                TextField("Wrong word", text: $newWrong)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundColor(NimbusColors.muted)
                TextField("Correct word", text: $newCorrect)
                    .textFieldStyle(.roundedBorder)
                Button(action: addEntry) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(NimbusGradients.primary)
                }
                .buttonStyle(.plain)
                .disabled(newWrong.isEmpty || newCorrect.isEmpty)
            }
            .padding(NimbusLayout.contentPadding)

            if dictionaryManager.entries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(NimbusGradients.primary)
                    Text("No corrections yet")
                        .font(.callout.weight(.medium))
                        .foregroundColor(NimbusColors.heading)
                    Text("Add words that get misheard during dictation.")
                        .font(.caption)
                        .foregroundColor(NimbusColors.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Entries list
                List {
                    ForEach(dictionaryManager.entries) { entry in
                        HStack {
                            Text(entry.wrong)
                                .font(.body)
                                .foregroundColor(NimbusColors.error)
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(NimbusColors.muted)
                            Text(entry.correct)
                                .font(.body.weight(.medium))
                                .foregroundColor(NimbusColors.ready)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        dictionaryManager.delete(at: offsets)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NimbusColors.warmBg)
    }

    private func addEntry() {
        dictionaryManager.add(wrong: newWrong, correct: newCorrect)
        newWrong = ""
        newCorrect = ""
    }
}
