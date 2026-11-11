import Foundation
import Testing
@testable import Loge

@MainActor
struct ProfileStoreTests {
    let defaults = makeDefaults()
    let legacy = makeDefaults()

    private func makeStore() -> ProfileStore { ProfileStore(defaults: defaults, legacyDefaults: legacy) }

    @Test func firstRunCreatesAProfileAndCopiesPreProfileData() throws {
        let progress = try JSONEncoder().encode([PlaybackProgress(item: movie("tt1"), video: nil, position: 600, duration: 6000, updatedAt: .now)])
        legacy.set(progress, forKey: StorageKey.legacyProgress)

        let store = makeStore()

        #expect(store.profiles.count == 1)
        #expect(store.active.name == "Profil 1")
        #expect(defaults.data(forKey: StorageKey.progress(store.activeID)) == progress)
        // Copied, not moved: the legacy data stays as a backup if the new storage is ever lost.
        #expect(legacy.data(forKey: StorageKey.legacyProgress) == progress)
        // The migrated data is what the library of that profile loads.
        #expect(LibraryStore(profileID: store.activeID, defaults: defaults).continueWatching().map(\.item.id) == ["tt1"])
    }

    @Test func profilesPersistAcrossLaunches() throws {
        let store = makeStore()
        let second = try store.create(name: "Léa")
        store.select(second.id)

        let reloaded = makeStore()
        #expect(reloaded.profiles.map(\.name) == ["Profil 1", "Léa"])
        #expect(reloaded.activeID == second.id)
    }

    @Test func validatesNames() throws {
        let store = makeStore()
        #expect(throws: ProfileError.emptyName) { try store.create(name: "   ") }
        #expect(throws: ProfileError.nameTooLong) { try store.create(name: String(repeating: "a", count: 17)) }
        #expect(throws: ProfileError.duplicateName) { try store.create(name: " profil 1 ") }
        let léa = try store.create(name: "Léa")
        // Renaming a profile to its own name is fine, to another profile's name (accents ignored) is not.
        try store.update(léa.id, name: "Léa", avatar: léa.avatar)
        #expect(throws: ProfileError.duplicateName) { try store.update(léa.id, name: "PROFIL 1", avatar: léa.avatar) }
        #expect(throws: ProfileError.duplicateName) { try store.create(name: "lea") }
    }

    @Test func capsTheNumberOfProfiles() throws {
        let store = makeStore()
        for index in 2...ProfileStore.maxProfiles { try store.create(name: "P\(index)") }
        #expect(!store.canAdd)
        #expect(throws: ProfileError.limitReached) { try store.create(name: "Trop") }
    }

    @Test func newProfilesGetDistinctAvatars() throws {
        let store = makeStore()
        let second = try store.create(name: "B")
        #expect(second.avatar != store.profiles[0].avatar)
        #expect(second.avatar.color != store.profiles[0].avatar.color)
    }

    @Test func updateRenamesAndChangesTheAvatar() throws {
        let store = makeStore()
        let id = store.activeID
        try store.update(id, name: "Papa", avatar: ProfileAvatar(color: .blue, symbol: .gamepad))
        #expect(store.active.name == "Papa")
        #expect(store.active.avatar == ProfileAvatar(color: .blue, symbol: .gamepad))
    }

    @Test func deleteRemovesTheProfileAndItsLibrary() throws {
        let store = makeStore()
        let second = try store.create(name: "Léa")
        let library = LibraryStore(profileID: second.id, defaults: defaults)
        library.toggleMyList(movie("tt9"))
        store.select(second.id)

        try store.delete(second.id)

        #expect(store.profiles.map(\.name) == ["Profil 1"])
        #expect(store.activeID == store.profiles[0].id) // the active profile fell back
        #expect(defaults.data(forKey: StorageKey.myList(second.id)) == nil)
        #expect(LibraryStore(profileID: second.id, defaults: defaults).myList.isEmpty)
    }

    @Test func cannotDeleteTheLastProfile() {
        let store = makeStore()
        #expect(throws: ProfileError.lastProfile) { try store.delete(store.activeID) }
        #expect(store.profiles.count == 1)
    }

    // MARK: Account sync (ADR 0023)

    @Test func firstLaunchProfileIsUntouchedUntilSomebodyUsesIt() throws {
        let store = makeStore()
        #expect(store.isUntouchedDefault)
        try store.update(store.activeID, name: "Agt", avatar: store.active.avatar)
        #expect(!store.isUntouchedDefault)
        #expect(!makeStore().isUntouchedDefault)
    }

    @Test func firstLaunchProfileWithPreProfileHistoryIsNotUntouched() throws {
        legacy.set(try JSONEncoder().encode([movie("tt1")]), forKey: StorageKey.legacyMyList)
        #expect(!makeStore().isUntouchedDefault)
    }

    @Test func accountProfilesReplaceTheUntouchedDefault() {
        let store = makeStore()
        let placeholder = store.activeID
        let remote = [
            Profile(id: UUID(), name: "Agt", avatar: ProfileAvatar(color: .blue, symbol: .face)),
            Profile(id: UUID(), name: "Léa", avatar: ProfileAvatar(color: .pink, symbol: .star)),
        ]
        store.adoptRemote(remote)
        #expect(store.profiles == remote)
        #expect(store.activeID == remote[0].id)
        #expect(!store.profiles.contains { $0.id == placeholder })
        #expect(store.adoptionCount == 1)
        // Only once: a used profile set is merged from then on, never replaced.
        store.adoptRemote([Profile(id: UUID(), name: "Autre", avatar: ProfileAvatar(color: .red, symbol: .face))])
        #expect(store.profiles == remote)
    }

    @Test func deletionIsRememberedAndNotUndoneByTheNextPull() throws {
        let store = makeStore()
        let lea = try store.create(name: "Léa")
        try store.delete(lea.id)
        #expect(store.deletedProfiles[lea.id] != nil)
        // The pull runs before the push that reports the deletion: the profile must not come back.
        store.mergeProfiles([lea])
        #expect(!store.profiles.contains { $0.id == lea.id })
        store.clearReportedDeletions([lea.id])
        #expect(makeStore().deletedProfiles.isEmpty)
    }

    @Test func remoteDeletionsRemoveProfilesButNeverTheLastOne() throws {
        let store = makeStore()
        let first = store.activeID
        let lea = try store.create(name: "Léa")
        store.select(lea.id)
        store.applyRemoteDeletions([lea.id: .now])
        #expect(store.profiles.map(\.id) == [first])
        #expect(store.activeID == first)
        store.applyRemoteDeletions([first: .now])
        #expect(store.profiles.map(\.id) == [first])
    }
}

@MainActor
struct ProfileLibraryTests {
    @Test func eachProfileHasItsOwnListAndProgress() {
        let defaults = makeDefaults()
        let a = UUID(), b = UUID()
        let library = LibraryStore(profileID: a, defaults: defaults)
        library.toggleMyList(movie("tt1"))
        library.updateProgress(item: movie("tt1"), video: nil, position: 900, duration: 6000)

        library.switchProfile(to: b)
        #expect(library.myList.isEmpty)
        #expect(library.continueWatching().isEmpty)
        library.toggleMyList(movie("tt2"))

        library.switchProfile(to: a)
        #expect(library.myList.map(\.id) == ["tt1"])
        #expect(library.resumePosition(for: "tt1") == 900)
        #expect(LibraryStore(profileID: b, defaults: defaults).myList.map(\.id) == ["tt2"])
    }
}
