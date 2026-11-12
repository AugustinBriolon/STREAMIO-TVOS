import Foundation
import Testing
@testable import Loge

@MainActor
struct LogoutHouseholdTests {
    @Test func clearLocalHouseholdResetsProfilesAddonsAndLibrary() throws {
        let defaults = makeDefaults()
        let profiles = ProfileStore(defaults: defaults, legacyDefaults: makeDefaults())
        profiles.plan = .ultra
        let lea = try profiles.create(name: "Léa")
        let library = LibraryStore(profileID: profiles.activeID, defaults: defaults)
        library.toggleMyList(movie("tt1"))
        library.switchProfile(to: lea.id)
        library.toggleMyList(movie("tt2"))

        let addonStorage = InMemorySecretStorage([])
        let addons = AddonStore(storage: addonStorage, legacyDefaults: makeDefaults())
        addons.plan = .ultra
        #expect(addons.add("https://torrentio.test"))

        let auth = AuthService()
        let engine = CloudSyncEngine(
            auth: auth,
            profiles: profiles,
            library: library,
            addons: addons,
            defaults: defaults
        )
        defaults.set(Date(), forKey: "loge.lastSyncDate")

        engine.clearLocalHousehold()

        #expect(profiles.profiles.map(\.name) == ["Profil 1"])
        #expect(profiles.isUntouchedDefault)
        #expect(profiles.plan == .free)
        #expect(addons.urls == AddonStore.defaultAddonURLs)
        #expect(addons.plan == .free)
        #expect(addons.personalAddonCount == 0)
        #expect(library.myList.isEmpty)
        #expect(library.profileID == profiles.activeID)
        #expect(engine.lastSyncDate == nil)
        #expect(defaults.object(forKey: "loge.lastSyncDate") == nil)
    }
}
