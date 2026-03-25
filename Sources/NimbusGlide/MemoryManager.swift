import Foundation
import SwiftUI
import CryptoKit

struct MemoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var rawTranscript: String
    var polishedText: String
    var timestamp: Date = Date()
}

class MemoryManager: ObservableObject {
    private static let storageKey = "nimbusglide_memory_entries"
    private static let encryptionKeyKeychainKey = "nimbusglide_memory_encryption_key"
    private static let maxEntries = 50

    @Published var entries: [MemoryEntry] {
        didSet { save() }
    }

    private var encryptionKey: SymmetricKey

    init() {
        self.encryptionKey = Self.loadOrCreateEncryptionKey()

        // Try loading encrypted data first
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            if let decrypted = Self.decrypt(data, key: self.encryptionKey),
               let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: decrypted) {
                self.entries = decoded
                return
            }
            // Might be unencrypted legacy data — try decoding directly and re-encrypt
            if let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: data) {
                self.entries = decoded
                // Re-save will encrypt it
                return
            }
        }
        self.entries = []
    }

    private func save() {
        guard let plaintext = try? JSONEncoder().encode(entries) else { return }
        if let encrypted = Self.encrypt(plaintext, key: encryptionKey) {
            UserDefaults.standard.set(encrypted, forKey: Self.storageKey)
        }
    }

    func addEntry(rawTranscript: String, polishedText: String) {
        let entry = MemoryEntry(rawTranscript: rawTranscript, polishedText: polishedText)
        entries.insert(entry, at: 0)

        // Trim to max entries
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }

    func deleteEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func clearAll() {
        entries.removeAll()
    }

    /// Returns the most recent entries for few-shot learning injection.
    func recentExamples(limit: Int = 5) -> [MemoryEntry] {
        return Array(entries.prefix(limit))
    }

    // MARK: - Encryption

    private static func loadOrCreateEncryptionKey() -> SymmetricKey {
        if let stored = KeychainHelper.load(key: encryptionKeyKeychainKey),
           let keyData = Data(base64Encoded: stored) {
            return SymmetricKey(data: keyData)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        KeychainHelper.save(key: encryptionKeyKeychainKey, value: keyData.base64EncodedString())
        return key
    }

    private static func encrypt(_ data: Data, key: SymmetricKey) -> Data? {
        guard let sealed = try? AES.GCM.seal(data, using: key) else { return nil }
        return sealed.combined
    }

    private static func decrypt(_ data: Data, key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(box, using: key) else { return nil }
        return decrypted
    }
}
