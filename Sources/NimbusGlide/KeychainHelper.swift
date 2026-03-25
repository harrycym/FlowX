import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.nimbusglide.app"

    // MARK: - Public API

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Try update first (faster path if key already exists)
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Key doesn't exist yet — add it
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Migration from plaintext files

    /// Migrates tokens from the old file-based storage to Keychain.
    /// Call once at launch. Reads any .tok files, stores them in Keychain, then deletes the files.
    static func migrateFromFilesIfNeeded() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NimbusGlide", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.lastPathComponent.hasSuffix(".tok") {
            // Extract key name: ".nimbusglide_access_token.tok" → "nimbusglide_access_token"
            var name = file.lastPathComponent
            if name.hasPrefix(".") { name = String(name.dropFirst()) }
            if name.hasSuffix(".tok") { name = String(name.dropLast(4)) }

            if let value = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                // Only migrate if not already in Keychain
                if load(key: name) == nil {
                    save(key: name, value: value)
                }
            }

            // Delete the plaintext file regardless
            try? FileManager.default.removeItem(at: file)
        }
    }
}
