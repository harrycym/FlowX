import Foundation
import SwiftUI

struct Profile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var instructions: String

    static let defaultProfiles: [Profile] = [
        Profile(name: "General", instructions: "Write naturally and conversationally. Use proper grammar and punctuation."),
        Profile(name: "Professional Email", instructions: "Format as a professional email. Use formal tone, proper salutations, and clear structure."),
        Profile(name: "Casual Chat", instructions: "Keep it casual and friendly. Use informal language appropriate for messaging apps like Slack or iMessage."),
        Profile(name: "AI Prompt", instructions: "Optimize the text as an AI prompt. Be clear, specific, and structured. Use precise language.")
    ]
}

class ProfileManager: ObservableObject {
    private static let profilesKey = "nimbusglide_profiles"
    private static let activeProfileKey = "nimbusglide_active_profile"

    @Published var profiles: [Profile] {
        didSet { save() }
    }

    @Published var activeProfileId: UUID? {
        didSet {
            if let id = activeProfileId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
            }
        }
    }

    var activeProfile: Profile? {
        guard let id = activeProfileId else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            self.profiles = decoded
        } else {
            self.profiles = Profile.defaultProfiles
        }

        if let idString = UserDefaults.standard.string(forKey: Self.activeProfileKey),
           let uuid = UUID(uuidString: idString),
           profiles.contains(where: { $0.id == uuid }) {
            self.activeProfileId = uuid
        } else {
            // Default to General (first profile) and persist it
            let firstId = profiles.first?.id
            self.activeProfileId = firstId
            if let id = firstId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
    }

    func addProfile(_ profile: Profile) {
        profiles.append(profile)
    }

    func deleteProfile(at offsets: IndexSet) {
        let idsToRemove = offsets.map { profiles[$0].id }
        profiles.remove(atOffsets: offsets)
        if let activeId = activeProfileId, idsToRemove.contains(activeId) {
            activeProfileId = profiles.first?.id
        }
    }

    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        }
    }
}
