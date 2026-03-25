import SwiftUI

struct DictionaryView: View {
    @State private var entries: [(wrong: String, correct: String)] = [
        (wrong: "nimble slide", correct: "NimbusGlide"),
        (wrong: "whisper flow", correct: "WhisperFlow"),
    ]
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

            // Entries list
            List {
                ForEach(entries.indices, id: \.self) { i in
                    HStack {
                        Text(entries[i].wrong)
                            .font(.body)
                            .foregroundColor(NimbusColors.error)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(NimbusColors.muted)
                        Text(entries[i].correct)
                            .font(.body.weight(.medium))
                            .foregroundColor(NimbusColors.ready)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    entries.remove(atOffsets: offsets)
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NimbusColors.warmBg)
    }

    private func addEntry() {
        entries.insert((wrong: newWrong, correct: newCorrect), at: 0)
        newWrong = ""
        newCorrect = ""
    }
}
