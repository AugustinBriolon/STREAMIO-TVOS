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
        // Empty list: delete the item so a failed update cannot leave stale addon URLs behind.
        if values.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
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
    /// Bases désactivées (toujours listées, ignorées à la lecture).
    public private(set) var disabledURLs: Set<String>

    private let storage: SecretStorage
    private let defaults: UserDefaults

    static let legacyListKey = "user_addon_urls_v2"
    static let legacySingleKey = "user_addon_url"
    static let disabledKey = "addon_disabled_urls"

    /// Official Stremio baselines restored on first launch / logout. Not counted toward the plan addon cap.
    public static let defaultAddonURLs: [String] = [
        "https://v3-channels.strem.io",       // YouTube
        "https://opensubtitles-v3.strem.io",  // OpenSubtitles v3
    ]

    /// Household plan cap for user-managed addons (Free = 1).
    public var plan: LogePlan = .free

    /// Addons the household added on top of the official defaults.
    public var personalAddonCount: Int {
        personalURLs.count
    }

    /// Baselines always offered with Loge (YouTube, OpenSubtitles) — not plan-capped, not deletable.
    public var includedURLs: [String] {
        urls.filter { Self.isDefaultAddonURL($0) }
    }

    /// User-installed stream addons — count toward `PlanLimits.maxAddons`, removable.
    public var personalURLs: [String] {
        urls.filter { !Self.isDefaultAddonURL($0) }
    }

    /// Bases actives pour fetch streams / dispo.
    public var activeURLs: [String] {
        urls.filter { !disabledURLs.contains($0) }
    }

    public var canAdd: Bool { PlanLimits.forPlan(plan).canAddAddon(currentCount: personalAddonCount) }

    public init(
        storage: SecretStorage = KeychainSecretStorage(),
        legacyDefaults: UserDefaults = .standard,
        defaults: UserDefaults = AppGroup.defaults
    ) {
        self.storage = storage
        self.defaults = defaults
        let loaded: [String]
        if let stored = storage.load() {
            loaded = stored
        } else {
            let migrated = Self.migrate(from: legacyDefaults, to: storage)
            if migrated.isEmpty {
                loaded = Self.defaultAddonURLs
                storage.save(loaded)
            } else {
                loaded = migrated
            }
        }
        self.urls = loaded
        let rawDisabled = defaults.stringArray(forKey: Self.disabledKey) ?? []
        self.disabledURLs = Set(rawDisabled.map(Self.cleanURL).filter { !$0.isEmpty && loaded.contains($0) })
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

    /// Returns false when the input is not an http(s) URL or the plan addon cap is reached.
    @discardableResult
    public func add(_ rawURL: String) -> Bool {
        let clean = Self.cleanURL(rawURL)
        guard let url = URL(string: clean), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else {
            return false
        }
        if urls.contains(clean) { return true }
        guard canAdd else { return false }
        urls.append(clean)
        storage.save(urls)
        return true
    }

    public func remove(_ url: String) {
        let clean = Self.cleanURL(url)
        guard !Self.isDefaultAddonURL(clean) else { return }
        urls.removeAll { $0 == clean }
        disabledURLs.remove(clean)
        storage.save(urls)
        persistDisabled()
    }

    public func isEnabled(_ url: String) -> Bool {
        !disabledURLs.contains(Self.cleanURL(url))
    }

    public func toggle(_ url: String) {
        let clean = Self.cleanURL(url)
        guard urls.contains(clean) else { return }
        if disabledURLs.contains(clean) {
            disabledURLs.remove(clean)
        } else {
            disabledURLs.insert(clean)
        }
        persistDisabled()
    }

    /// Guest / post-logout baseline: official YouTube + OpenSubtitles only, Free caps.
    public func resetToDefaults() {
        urls = Self.defaultAddonURLs
        plan = .free
        disabledURLs = []
        storage.save(urls)
        persistDisabled()
    }

    nonisolated public static func isDefaultAddonURL(_ url: String) -> Bool {
        defaultAddonURLs.contains(cleanURL(url))
    }

    /// Label court pour la liste Réglages (sans exposer de clé).
    public static func displayTitle(_ url: String) -> String {
        let clean = cleanURL(url)
        if clean.contains("v3-channels.strem.io") { return "YouTube" }
        if clean.contains("opensubtitles") { return "OpenSubtitles" }
        return maskedDisplay(clean)
    }

    private func persistDisabled() {
        defaults.set(Array(disabledURLs).sorted(), forKey: Self.disabledKey)
    }

    /// Accepts a manifest URL or a base URL; returns the base URL without trailing slash.
    /// `stremio://` links copied from addon pages are converted to https.
    nonisolated static func cleanURL(_ raw: String) -> String {
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
