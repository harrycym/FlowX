import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var usageTracker: UsageTracker
    @State private var selectedProfileId: UUID?
    @State private var showingAddSheet = false
    @State private var showUpgradeAlert = false

    var body: some View {
        HSplitView {
            // Sidebar: profile list
            VStack(spacing: 0) {
                List(selection: $selectedProfileId) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == profileManager.activeProfileId
                        )
                        .tag(profile.id)
                    }
                    .onDelete { offsets in
                        profileManager.deleteProfile(at: offsets)
                        if let id = selectedProfileId,
                           !profileManager.profiles.contains(where: { $0.id == id }) {
                            selectedProfileId = profileManager.profiles.first?.id
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: handleAddProfile) {
                        Label("Add Profile", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if !usageTracker.isPro {
                        Text("\(profileManager.profiles.count)/\(ProfileManager.freeProfileLimit)")
                            .font(.caption)
                            .foregroundColor(profileManager.profiles.count >= ProfileManager.freeProfileLimit ? .orange : .secondary)
                    } else {
                        Text("\(profileManager.profiles.count) profiles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

            // Detail editor
            if let id = selectedProfileId,
               let index = profileManager.profiles.firstIndex(where: { $0.id == id }) {
                ProfileEditor(
                    profile: $profileManager.profiles[index],
                    isActive: id == profileManager.activeProfileId,
                    onSetActive: { profileManager.activeProfileId = id },
                    onDelete: {
                        let offsets = IndexSet(integer: index)
                        profileManager.deleteProfile(at: offsets)
                        selectedProfileId = profileManager.profiles.first?.id
                    }
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a profile to edit")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddProfileView(profileManager: profileManager, isPresented: $showingAddSheet)
        }
        .alert("Profile limit reached", isPresented: $showUpgradeAlert) {
            Button("Upgrade to Pro") {
                NotificationCenter.default.post(name: .nimbusglideNavigateToAccount, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free accounts can have up to \(ProfileManager.freeProfileLimit) profiles. Upgrade to Pro for unlimited profiles.")
        }
        .onAppear {
            if selectedProfileId == nil {
                selectedProfileId = profileManager.activeProfileId ?? profileManager.profiles.first?.id
            }
        }
    }

    private func handleAddProfile() {
        if profileManager.canAddProfile(isPro: usageTracker.isPro) {
            showingAddSheet = true
        } else {
            showUpgradeAlert = true
        }
    }
}

// MARK: - Profile Row

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(isActive ? .semibold : .regular))
                Text(profile.instructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Profile Editor

private struct ProfileEditor: View {
    @Binding var profile: Profile
    let isActive: Bool
    let onSetActive: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Profile Name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.medium))

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundColor(.accentColor)
                } else {
                    Button("Set Active") { onSetActive() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.7))
                .help("Delete this profile")
                .alert("Delete \"\(profile.name)\"?", isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) { onDelete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This profile will be permanently deleted.")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions")
                    .font(.headline)
                Text("Tell NimbusGlide how to process dictations with this profile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $profile.instructions)
                .font(.body)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2))
                )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Add Profile

private struct AddProfileView: View {
    let profileManager: ProfileManager
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var instructions = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("New Profile")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.subheadline.weight(.medium))
                TextField("e.g. Professional Email", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions")
                    .font(.subheadline.weight(.medium))
                Text("Tell NimbusGlide how to format your dictation with this profile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $instructions)
                    .frame(height: 120)
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
                    profileManager.addProfile(Profile(name: name, instructions: instructions))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420, height: 340)
    }
}
