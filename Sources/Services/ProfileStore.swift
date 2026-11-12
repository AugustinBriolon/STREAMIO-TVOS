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
        case .limitReached: return "Limite de profils atteinte pour votre offre."
        case .lastProfile: return "Au moins un profil est nécessaire."
        }
    }
}

/// Profiles of the household and which one is active (ADR 0014). Each profile has its own list and
/// progress (`LibraryStore`); addons stay shared. There is always at least one profile.
@MainActor
@Observable
public final class ProfileStore {
    /// Absolute ceiling (Ultra). Prefer `PlanLimits.forPlan(plan).maxProfiles` for the active offer.
    public nonisolated static let maxProfiles = 6
    public nonisolated static let maxNameLength = 16

    public private(set) var profiles: [Profile]
    public private(set) var activeID: UUID
    /// Deleted profile ids and when, sent to the account so other devices delete them too (ADR 0023).
    public private(set) var deletedProfiles: [UUID: Date]
    /// The first-launch "Profil 1", never renamed and never joined by another profile: an account's
    /// profiles replace it instead of being added next to it.
    public private(set) var isUntouchedDefault: Bool
    /// Bumped when the UI must show « Qui regarde ? » (login, or account profiles replacing the guest).
    public private(set) var adoptionCount = 0
    /// Household plan; defaults to Free until AuthService refreshes the account plan.
    public var plan: LogePlan = .free

    /// Empty guest placeholder that must not be uploaded next to the account's real profiles.
    public var shouldAdoptAccountProfiles: Bool {
        isUntouchedDefault || (profiles.count == 1 && profiles[0].name == "Profil 1")
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var active: Profile { profiles.first { $0.id == activeID } ?? profiles[0] }
    public var canAdd: Bool { PlanLimits.forPlan(plan).canAddProfile(currentCount: profiles.count) }

    /// Loads the stored profiles. The first run creates "Profil 1" and copies the pre-profile list and
    /// progress (standard defaults) into it, so nothing watched before profiles existed is lost.
    init(defaults: UserDefaults = AppGroup.defaults, legacyDefaults: UserDefaults = .standard,
                makeID: () -> UUID = UUID.init) {
        self.defaults = defaults
        deletedProfiles = defaults.data(forKey: StorageKey.deletedProfiles)
            .flatMap { try? JSONDecoder().decode([UUID: Date].self, from: $0) } ?? [:]
        if let data = defaults.data(forKey: StorageKey.profiles),
           let stored = try? JSONDecoder().decode([Profile].self, from: data), !stored.isEmpty {
            profiles = stored
            let activeID = defaults.string(forKey: StorageKey.activeProfile).flatMap(UUID.init(uuidString:))
            self.activeID = stored.contains { $0.id == activeID } ? activeID! : stored[0].id
            // Installs from before this flag: a lone, still-named "Profil 1" is taken as untouched
            // (the sync engine also requires its library to be empty before replacing it).
            isUntouchedDefault = defaults.object(forKey: StorageKey.untouchedDefaultProfile) == nil
                ? stored.count == 1 && stored[0].name == "Profil 1"
                : defaults.bool(forKey: StorageKey.untouchedDefaultProfile)
        } else {
            let first = Profile(id: makeID(), name: "Profil 1", avatar: .suggested(avoiding: []))
            profiles = [first]
            activeID = first.id
            // A profile that inherits pre-profile history is somebody's: it must not be replaced.
            isUntouchedDefault = !Self.migrateLegacyLibrary(from: legacyDefaults, to: defaults, profileID: first.id)
            persist()
        }
    }

    @discardableResult
    public func create(name: String, avatar: ProfileAvatar? = nil) throws -> Profile {
        guard canAdd else { throw ProfileError.limitReached }
        let clean = try validated(name, excluding: nil)
        let profile = Profile(id: UUID(), name: clean, avatar: avatar ?? .suggested(avoiding: profiles))
        profiles.append(profile)
        isUntouchedDefault = false
        persist()
        return profile
    }

    public func update(_ id: UUID, name: String, avatar: ProfileAvatar) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = try validated(name, excluding: id)
        profiles[index].avatar = avatar
        isUntouchedDefault = false
        persist()
    }

    /// Deletes a profile and everything stored for it. The active profile falls back to the first remaining one.
    public func delete(_ id: UUID) throws {
        guard profiles.count > 1 else { throw ProfileError.lastProfile }
        guard profiles.contains(where: { $0.id == id }) else { return }
        remove(id, deletedAt: Date())
        persist()
    }

    public func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }), id != activeID else { return }
        activeID = id
        persist()
    }

    /// Ask RootView to open « Qui regarde ? » after a successful account connection.
    public func requestProfilePicker() {
        adoptionCount += 1
    }

    /// Wipes every local profile (and its library keys) and recreates an untouched "Profil 1".
    /// Used on intentional logout / account deletion so the next session cannot inherit the foyer.
    public func resetToGuest(makeID: () -> UUID = UUID.init) {
        for profile in profiles {
            LibraryStore.erase(profileID: profile.id, from: defaults)
        }
        let first = Profile(id: makeID(), name: "Profil 1", avatar: .suggested(avoiding: []))
        profiles = [first]
        activeID = first.id
        deletedProfiles = [:]
        isUntouchedDefault = true
        plan = .free
        persist()
    }

    /// Merges remote profiles pulled from cloud sync, preserving local count limits. A profile deleted
    /// here but not yet reported to the account is not brought back.
    public func mergeProfiles(_ incoming: [Profile]) {
        var updated = profiles
        var changed = false
        for profile in incoming where deletedProfiles[profile.id] == nil {
            if let idx = updated.firstIndex(where: { $0.id == profile.id }) {
                if updated[idx].name != profile.name || updated[idx].avatar != profile.avatar {
                    updated[idx] = profile
                    changed = true
                }
            } else if updated.count < Self.maxProfiles {
                updated.append(profile)
                changed = true
            }
        }
        if changed {
            profiles = updated
            persist()
        }
    }

    /// The account's profiles replace the untouched first-launch profile, whose (empty) data is erased.
    /// Callers check that this device's library holds nothing for it first.
    public func adoptRemote(_ incoming: [Profile]) {
        let usable = incoming.filter { deletedProfiles[$0.id] == nil }.prefix(Self.maxProfiles)
        guard isUntouchedDefault, let first = usable.first else { return }
        for placeholder in profiles where !usable.contains(where: { $0.id == placeholder.id }) {
            LibraryStore.erase(profileID: placeholder.id, from: defaults)
        }
        profiles = Array(usable)
        activeID = first.id
        isUntouchedDefault = false
        adoptionCount += 1
        persist()
    }

    /// Profiles deleted on another device or on the web. The last profile is never removed.
    public func applyRemoteDeletions(_ deletions: [UUID: Date]) {
        var changed = false
        for (id, date) in deletions where profiles.contains(where: { $0.id == id }) && profiles.count > 1 {
            remove(id, deletedAt: date)
            changed = true
        }
        if changed { persist() }
    }

    /// The account now knows about these deletions: no need to send them again.
    public func clearReportedDeletions(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { deletedProfiles.removeValue(forKey: id) }
        persist()
    }

    // MARK: Private

    private func remove(_ id: UUID, deletedAt date: Date) {
        profiles.removeAll { $0.id == id }
        LibraryStore.erase(profileID: id, from: defaults)
        deletedProfiles[id] = date
        if activeID == id { activeID = profiles[0].id }
    }

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
        if let data = try? JSONEncoder().encode(deletedProfiles) { defaults.set(data, forKey: StorageKey.deletedProfiles) }
        defaults.set(activeID.uuidString, forKey: StorageKey.activeProfile)
        defaults.set(isUntouchedDefault, forKey: StorageKey.untouchedDefaultProfile)
    }

    /// Copies, never moves: the legacy keys stay as a backup. A first version moved them, and when the
    /// shared container was recreated empty (a build without the App Group replaced the app) the history was
    /// lost for good. They are tiny, so keeping them costs nothing.
    /// Returns whether anything was copied.
    @discardableResult
    private static func migrateLegacyLibrary(from legacy: UserDefaults, to defaults: UserDefaults, profileID: UUID) -> Bool {
        let list = legacy.data(forKey: StorageKey.legacyMyList)
        let progress = legacy.data(forKey: StorageKey.legacyProgress)
        if let list { defaults.set(list, forKey: StorageKey.myList(profileID)) }
        if let progress { defaults.set(progress, forKey: StorageKey.progress(profileID)) }
        return list != nil || progress != nil
    }
}
