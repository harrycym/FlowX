import SwiftUI

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

class SnippetsManager: ObservableObject {
    private static let storageKey = "nimbusglide_snippets"

    @Published var snippets: [Snippet] {
        didSet { save() }
    }

    private static let defaultSnippets: [Snippet] = [
        Snippet(trigger: "my address", expansion: "742 Evergreen Terrace, Springfield, IL 62704"),
        Snippet(trigger: "my bio", expansion: "Software engineer and entrepreneur passionate about building AI-powered tools that make everyday tasks effortless. Previously at Google, now focused on creating the future of voice interfaces."),
        Snippet(trigger: "my sign off", expansion: "Best regards, and thank you for your time. Please don't hesitate to reach out if you have any questions or need anything else from me."),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            self.snippets = decoded
        } else {
            self.snippets = Self.defaultSnippets
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func add(trigger: String, expansion: String) {
        snippets.insert(Snippet(trigger: trigger, expansion: expansion), at: 0)
    }

    func delete(at offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
    }

    /// Expands any snippet triggers found in the text.
    /// Case-insensitive matching.
    func expand(_ text: String) -> String {
        var result = text
        for snippet in snippets {
            // Case-insensitive replace
            let range = result.range(of: snippet.trigger, options: .caseInsensitive)
            if let range {
                result.replaceSubrange(range, with: snippet.expansion)
            }
        }
        return result
    }
}

struct SnippetsView: View {
    @EnvironmentObject var snippetsManager: SnippetsManager
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Snippets")
                        .font(NimbusFonts.pageTitle)
                        .foregroundColor(NimbusColors.heading)
                    Text("Say a trigger phrase during dictation and NimbusGlide will expand it into the full text automatically.")
                        .font(NimbusFonts.caption)
                        .foregroundColor(NimbusColors.muted)
                        .lineSpacing(2)
                }
                Spacer()
                Button(action: { showAddSheet = true }) {
                    Label("Add Snippet", systemImage: "plus")
                        .font(NimbusFonts.bodyMedium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(NimbusLayout.contentPadding)

            Divider()

            if snippetsManager.snippets.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(NimbusGradients.primary)
                    Text("No snippets yet")
                        .font(NimbusFonts.bodyMedium)
                        .foregroundColor(NimbusColors.heading)
                    Text("Add trigger phrases that expand into longer text.")
                        .font(NimbusFonts.caption)
                        .foregroundColor(NimbusColors.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(snippetsManager.snippets) { snippet in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\"\(snippet.trigger)\"")
                                    .font(NimbusFonts.bodyMedium)
                                    .foregroundColor(NimbusColors.violet)
                                Text(snippet.expansion)
                                    .font(NimbusFonts.body)
                                    .foregroundColor(NimbusColors.body)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button(action: {
                                if let idx = snippetsManager.snippets.firstIndex(where: { $0.id == snippet.id }) {
                                    snippetsManager.delete(at: IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(NimbusFonts.body)
                                    .foregroundColor(NimbusColors.error.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete { offsets in
                        snippetsManager.delete(at: offsets)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NimbusColors.warmBg)
        .sheet(isPresented: $showAddSheet) {
            AddSnippetView(isPresented: $showAddSheet)
                .environmentObject(snippetsManager)
        }
    }
}

private struct AddSnippetView: View {
    @EnvironmentObject var snippetsManager: SnippetsManager
    @Binding var isPresented: Bool
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Snippet")
                .font(NimbusFonts.sectionHeader)

            TextField("Trigger phrase (e.g. \"my email\")", text: $trigger)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Expansion")
                    .font(NimbusFonts.bodyMedium)
                TextEditor(text: $expansion)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    snippetsManager.add(trigger: trigger, expansion: expansion)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.isEmpty || expansion.isEmpty)
            }
        }
        .padding(NimbusLayout.contentPadding)
        .frame(width: NimbusLayout.sheetWidth, height: 260)
    }
}
