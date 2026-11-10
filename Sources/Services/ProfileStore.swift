import Foundation
import Observation

public enum ProfileError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case duplicateName
    case limitReached
    case lastProfile

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Donnez un nom au profil."
        case .nameTooLong: return "Le nom est trop long (\(ProfileStore.maxNameLength) caractères maximum)."
        case .duplicateName: return "Un profil porte déjà ce nom."
        case .limitReached: return "Vous ne pouvez pas avoir plus de \(ProfileStore.maxProfiles) profils."
        case .lastProfile: return "Au moins un profil est nécessaire."
        }
    }
}

/// Profiles of the household and which one is active (ADR 0014). Each profile has its own list and
/// progress (`LibraryStore`); addons stay shared. There is always at least one profile.
@MainActor
@Observable
public final class ProfileStore {
    public nonisolated static let maxProfiles = 6
    public nonisolated static let maxNameLength = 16

    public private(set) var profiles: [Profile]
    public private(set) var activeID: UUID

    @ObservationIgnored private let defaults: UserDefaults

    public var active: Profile { profiles.first { $0.id == activeID } ?? profiles[0] }
    public var canAdd: Bool { profiles.count < Self.maxProfiles }

    /// Loads the stored profiles. The first run creates "Profil 1" and copies the pre-profile list and
    /// progress (standard defaults) into it, so nothing watched before profiles existed is lost.
    init(defaults: UserDefaults = AppGroup.defaults, legacyDefaults: UserDefaults = .standard,
                makeID: () -> UUID = UUID.init) {
        self.defaults = defaults
        if let data = defaults.data(forKey: StorageKey.profiles),
           let stored = try? JSONDecoder().decode([Profile].self, from: data), !stored.isEmpty {
            profiles = stored
            let activeID = defaults.string(forKey: StorageKey.activeProfile).flatMap(UUID.init(uuidString:))
            self.activeID = stored.contains { $0.id == activeID } ? activeID! : stored[0].id
        } else {
            let first = Profile(id: makeID(), name: "Profil 1", avatar: .suggested(avoiding: []))
            profiles = [first]
            activeID = first.id
            Self.migrateLegacyLibrary(from: legacyDefaults, to: defaults, profileID: first.id)
            persist()
        }
    }

    @discardableResult
    public func create(name: String, avatar: ProfileAvatar? = nil) throws -> Profile {
        guard canAdd else { throw ProfileError.limitReached }
        let clean = try validated(name, excluding: nil)
        let profile = Profile(id: UUID(), name: clean, avatar: avatar ?? .suggested(avoiding: profiles))
        profiles.append(profile)
        persist()
        return profile
    }

    public func update(_ id: UUID, name: String, avatar: ProfileAvatar) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = try validated(name, excluding: id)
        profiles[index].avatar = avatar
        persist()
    }

    /// Deletes a profile and everything stored for it. The active profile falls back to the first remaining one.
    public func delete(_ id: UUID) throws {
        guard profiles.count > 1 else { throw ProfileError.lastProfile }
        guard profiles.contains(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        LibraryStore.erase(profileID: id, from: defaults)
        if activeID == id { activeID = profiles[0].id }
        persist()
    }

    public func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }), id != activeID else { return }
        activeID = id
        persist()
    }

    // MARK: Private

    private func validated(_ name: String, excluding id: UUID?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ProfileError.emptyName }
        guard clean.count <= Self.maxNameLength else { throw ProfileError.nameTooLong }
        let taken = profiles.contains { $0.id != id && $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        guard !taken else { throw ProfileError.duplicateName }
        return clean
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: StorageKey.profiles) }
        defaults.set(activeID.uuidString, forKey: StorageKey.activeProfile)
    }

    /// Copies, never moves: the legacy keys stay as a backup. A first version moved them, and when the
    /// shared container was recreated empty (a build without the App Group replaced the app) the history was
    /// lost for good. They are tiny, so keeping them costs nothing.
    private static func migrateLegacyLibrary(from legacy: UserDefaults, to defaults: UserDefaults, profileID: UUID) {
        if let list = legacy.data(forKey: StorageKey.legacyMyList) {
            defaults.set(list, forKey: StorageKey.myList(profileID))
        }
        if let progress = legacy.data(forKey: StorageKey.legacyProgress) {
            defaults.set(progress, forKey: StorageKey.progress(profileID))
        }
    }
}
