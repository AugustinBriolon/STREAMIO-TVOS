import Foundation
import Observation
import Security

/// Persists a list of secret strings. Addon URLs embed debrid API keys, so they never go to UserDefaults.
public protocol SecretStorage: Sendable {
    func load() -> [String]?
    @discardableResult func save(_ values: [String]) -> Bool
}

public struct KeychainSecretStorage: SecretStorage {
    private let service: String
    private let account: String

    public init(service: String = "com.h6245.loge.addons", account: String = "addon-urls") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> [String]? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    public func save(_ values: [String]) -> Bool {
        guard let data = try? JSONEncoder().encode(values) else { return false }
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}

@MainActor
@Observable
public final class AddonStore {
    public private(set) var urls: [String]

    private let storage: SecretStorage

    static let legacyListKey = "user_addon_urls_v2"
    static let legacySingleKey = "user_addon_url"

    public init(storage: SecretStorage = KeychainSecretStorage(), legacyDefaults: UserDefaults = .standard) {
        self.storage = storage
        if let stored = storage.load() {
            urls = stored
        } else {
            urls = Self.migrate(from: legacyDefaults, to: storage)
        }
    }

    /// Moves pre-2.0 plaintext URLs into the Keychain; legacy keys are erased only once the Keychain write succeeds.
    private static func migrate(from defaults: UserDefaults, to storage: SecretStorage) -> [String] {
        let legacy = defaults.stringArray(forKey: legacyListKey)
            ?? defaults.string(forKey: legacySingleKey).map { [$0] }
            ?? []
        let cleaned = legacy.map(cleanURL).filter { !$0.isEmpty }
        if cleaned.isEmpty || storage.save(cleaned) {
            defaults.removeObject(forKey: legacyListKey)
            defaults.removeObject(forKey: legacySingleKey)
        }
        return cleaned
    }

    /// Returns false when the input is not an http(s) URL.
    @discardableResult
    public func add(_ rawURL: String) -> Bool {
        let clean = Self.cleanURL(rawURL)
        guard let url = URL(string: clean), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else {
            return false
        }
        if !urls.contains(clean) {
            urls.append(clean)
            storage.save(urls)
        }
        return true
    }

    public func remove(_ url: String) {
        urls.removeAll { $0 == url }
        storage.save(urls)
    }

    /// Accepts a manifest URL or a base URL; returns the base URL without trailing slash.
    /// `stremio://` links copied from addon pages are converted to https.
    static func cleanURL(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasPrefix("stremio://") {
            base = "https://" + base.dropFirst("stremio://".count)
        }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/manifest.json") {
            base = String(base.dropLast("/manifest.json".count))
        }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    /// Host only, so debrid keys embedded in the path are never displayed.
    public static func maskedDisplay(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return "Addon" }
        return URL(string: url)?.path.count ?? 0 > 1 ? "\(host)/••••" : host
    }
}
