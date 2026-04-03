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
                            .font(NimbusFonts.caption)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if !usageTracker.isPro {
                        Text("\(profileManager.profiles.count)/\(ProfileManager.freeProfileLimit)")
                            .font(NimbusFonts.caption)
                            .foregroundColor(profileManager.profiles.count >= ProfileManager.freeProfileLimit ? NimbusColors.processing : NimbusColors.muted)
                    } else {
                        Text("\(profileManager.profiles.count) profiles")
                            .font(NimbusFonts.caption)
                            .foregroundColor(NimbusColors.muted)
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
                        .font(.system(size: NimbusLayout.emptyStateIconSize, weight: .light))
                        .foregroundStyle(NimbusGradients.primary)
                    Text("Select a profile to edit")
                        .foregroundColor(NimbusColors.muted)
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
        .background(NimbusColors.warmBg)
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
                    .font(isActive ? NimbusFonts.bodyMedium : NimbusFonts.body)
                Text(profile.instructions)
                    .font(NimbusFonts.caption)
                    .foregroundColor(NimbusColors.muted)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(NimbusColors.indigo)
                    .font(NimbusFonts.caption)
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
                        .font(NimbusFonts.bodyMedium)
                        .foregroundColor(NimbusColors.indigo)
                } else {
                    Button("Set Active") { onSetActive() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(NimbusFonts.body)
                }
                .buttonStyle(.plain)
                .foregroundColor(NimbusColors.error.opacity(0.7))
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
                    .font(NimbusFonts.sectionHeader)
                Text("Tell NimbusGlide how to process dictations with this profile.")
                    .font(NimbusFonts.caption)
                    .foregroundColor(NimbusColors.muted)
            }

            TextEditor(text: $profile.instructions)
                .font(NimbusFonts.body)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2))
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 20)
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
                    .font(NimbusFonts.bodyMedium)
                TextField("e.g. Professional Email", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions")
                    .font(NimbusFonts.bodyMedium)
                Text("Tell NimbusGlide how to format your dictation with this profile.")
                    .font(NimbusFonts.caption)
                    .foregroundColor(NimbusColors.muted)
                TextEditor(text: $instructions)
                    .frame(height: 180)
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
        .padding(NimbusLayout.contentPadding)
        .frame(width: 560, height: 420)
    }
}
