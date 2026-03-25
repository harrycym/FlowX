import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var memoryManager: MemoryManager
    @State private var searchText = ""
    @State private var selectedEntryId: UUID?

    private var filteredEntries: [MemoryEntry] {
        if searchText.isEmpty { return memoryManager.entries }
        return memoryManager.entries.filter {
            $0.rawTranscript.localizedCaseInsensitiveContains(searchText) ||
            $0.polishedText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(memoryManager.entries.count) dictations")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !memoryManager.entries.isEmpty {
                    Button("Clear All") {
                        memoryManager.clearAll()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if memoryManager.entries.isEmpty {
                emptyState
            } else {
                List(selection: $selectedEntryId) {
                    ForEach(filteredEntries) { entry in
                        HistoryRow(entry: entry)
                            .tag(entry.id)
                    }
                    .onDelete { offsets in
                        let idsToDelete = offsets.map { filteredEntries[$0].id }
                        for id in idsToDelete {
                            memoryManager.deleteEntry(id: id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "Search dictations")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No dictation history")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Your transcriptions will appear here\nafter your first dictation.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let entry: MemoryEntry
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: copyText) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy result")
            }

            Text(entry.rawTranscript)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(entry.polishedText)
                .font(.callout)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    private func copyText() {
        let debugText = "Raw Input:\n\(entry.rawTranscript)\n\nFormatted Output:\n\(entry.polishedText)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
