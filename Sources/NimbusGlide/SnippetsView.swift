import SwiftUI

struct SnippetsView: View {
    @State private var snippets: [Snippet] = [
        Snippet(trigger: "my email", expansion: "harry@nimbusglide.ai"),
        Snippet(trigger: "my address", expansion: "123 Innovation Drive, San Francisco, CA 94105"),
    ]
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Snippets")
                        .font(.title2.weight(.bold))
                        .foregroundColor(NimbusColors.heading)
                    Text("Say a trigger phrase during dictation and NimbusGlide will expand it into the full text automatically.")
                        .font(.caption)
                        .foregroundColor(NimbusColors.muted)
                        .lineSpacing(2)
                }
                Spacer()
                Button(action: { showAddSheet = true }) {
                    Label("Add Snippet", systemImage: "plus")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(NimbusLayout.contentPadding)

            Divider()

            if snippets.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(NimbusGradients.primary)
                    Text("No snippets yet")
                        .font(.callout.weight(.medium))
                        .foregroundColor(NimbusColors.heading)
                    Text("Add trigger phrases that expand into longer text.")
                        .font(.caption)
                        .foregroundColor(NimbusColors.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(snippets) { snippet in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\"\\(snippet.trigger)\"")
                                    .font(.callout.weight(.semibold))
                                    .foregroundColor(NimbusColors.violet)
                                Spacer()
                            }
                            Text(snippet.expansion)
                                .font(.callout)
                                .foregroundColor(NimbusColors.body)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        snippets.remove(atOffsets: offsets)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NimbusColors.warmBg)
        .sheet(isPresented: $showAddSheet) {
            AddSnippetView(snippets: $snippets, isPresented: $showAddSheet)
        }
    }
}

struct Snippet: Identifiable {
    let id = UUID()
    var trigger: String
    var expansion: String
}

private struct AddSnippetView: View {
    @Binding var snippets: [Snippet]
    @Binding var isPresented: Bool
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Snippet")
                .font(.headline)

            TextField("Trigger phrase (e.g. \"my email\")", text: $trigger)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Expansion")
                    .font(.subheadline)
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
                    snippets.insert(Snippet(trigger: trigger, expansion: expansion), at: 0)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.isEmpty || expansion.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 260)
    }
}
