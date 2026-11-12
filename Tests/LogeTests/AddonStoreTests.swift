import Foundation
import Testing
@testable import Loge

@MainActor
struct AddonStoreTests {
    @Test func migratesLegacyDefaultsIntoSecretStorage() {
        let defaults = makeDefaults()
        defaults.set(["https://a.io/manifest.json"], forKey: AddonStore.legacyListKey)
        let storage = InMemorySecretStorage()
        let store = AddonStore(storage: storage, legacyDefaults: defaults)
        #expect(store.urls == ["https://a.io"])
        #expect(storage.values == ["https://a.io"])
        #expect(defaults.stringArray(forKey: AddonStore.legacyListKey) == nil)
    }

    @Test func seedsOfficialDefaultsWhenStoreIsUnconfigured() {
        let storage = InMemorySecretStorage()
        let store = AddonStore(storage: storage, legacyDefaults: makeDefaults())
        #expect(store.urls == AddonStore.defaultAddonURLs)
        #expect(storage.values == AddonStore.defaultAddonURLs)
        #expect(store.urls.count == 2)
        #expect(store.personalAddonCount == 0)
    }

    @Test func respectsAddonPlanCapIgnoringOfficialDefaults() {
        let storage = InMemorySecretStorage(AddonStore.defaultAddonURLs)
        let store = AddonStore(storage: storage, legacyDefaults: makeDefaults())
        store.plan = .free
        #expect(store.urls.count == 2)
        #expect(store.add("https://a.io"))
        #expect(!store.add("https://b.io"))
        store.plan = .pro
        #expect(store.add("https://b.io"))
    }

    @Test func doesNotReseedWhenUserClearedAddons() {
        let store = AddonStore(storage: InMemorySecretStorage([]), legacyDefaults: makeDefaults())
        #expect(store.urls.isEmpty)
    }

    @Test func resetToDefaultsRestoresOfficialAddonsAndPlan() {
        let storage = InMemorySecretStorage([])
        let store = AddonStore(storage: storage, legacyDefaults: makeDefaults())
        store.plan = .ultra
        #expect(store.add("https://a.io"))
        store.resetToDefaults()
        #expect(store.urls == AddonStore.defaultAddonURLs)
        #expect(store.plan == .free)
        #expect(store.personalAddonCount == 0)
        #expect(storage.values == AddonStore.defaultAddonURLs)
    }

    @Test func inMemorySaveEmptyReplacesPreviousUrls() {
        let storage = InMemorySecretStorage(["https://old.io"])
        #expect(storage.save([]))
        #expect(storage.values == [])
        #expect(storage.load() == [])
    }

    @Test func keepsLegacyDataWhenSecretStorageFails() {
        let defaults = makeDefaults()
        defaults.set("https://a.io", forKey: AddonStore.legacySingleKey)
        let storage = InMemorySecretStorage()
        storage.failsOnSave = true
        let store = AddonStore(storage: storage, legacyDefaults: defaults)
        #expect(store.urls == ["https://a.io"])
        #expect(defaults.string(forKey: AddonStore.legacySingleKey) == "https://a.io")
    }

    @Test func normalisesAndValidatesURLs() {
        let store = AddonStore(storage: InMemorySecretStorage([]), legacyDefaults: makeDefaults())
        store.plan = .ultra
        #expect(store.add("  https://a.io/key/manifest.json/ "))
        #expect(store.add("stremio://b.io/manifest.json"))
        #expect(!store.add("javascript:alert(1)"))
        #expect(!store.add("not a url"))
        store.add("https://a.io/key")
        #expect(store.urls == ["https://a.io/key", "https://b.io"])
        store.remove("https://b.io")
        #expect(store.urls == ["https://a.io/key"])
    }

    @Test func maskedDisplayHidesPath() {
        #expect(AddonStore.maskedDisplay("https://torrentio.strem.fun/realdebrid=SECRET") == "torrentio.strem.fun/••••")
        #expect(AddonStore.maskedDisplay("https://a.io") == "a.io")
    }

    @Test func displayTitleUsesFriendlyNamesForDefaults() {
        #expect(AddonStore.displayTitle("https://v3-channels.strem.io") == "YouTube")
        #expect(AddonStore.displayTitle("https://opensubtitles-v3.strem.io") == "OpenSubtitles")
    }

    @Test func toggleDisablesWithoutRemoving() {
        let suite = "tests.addons.disabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let profile = UUID()
        let storage = InMemorySecretStorage(AddonStore.defaultAddonURLs)
        let store = AddonStore(storage: storage, legacyDefaults: makeDefaults(), defaults: defaults, profileID: profile)
        let youtube = AddonStore.defaultAddonURLs[0]
        #expect(store.isEnabled(youtube))
        #expect(store.activeURLs.count == 2)
        store.toggle(youtube)
        #expect(!store.isEnabled(youtube))
        #expect(store.urls.contains(youtube))
        #expect(store.activeURLs == [AddonStore.defaultAddonURLs[1]])
        let reloaded = AddonStore(storage: storage, legacyDefaults: makeDefaults(), defaults: defaults, profileID: profile)
        #expect(!reloaded.isEnabled(youtube))
    }

    @Test func enableDisableIsPerProfile() {
        let suite = "tests.addons.disabled.profiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let storage = InMemorySecretStorage(AddonStore.defaultAddonURLs)
        let a = UUID()
        let b = UUID()
        let store = AddonStore(storage: storage, legacyDefaults: makeDefaults(), defaults: defaults, profileID: a)
        let youtube = AddonStore.defaultAddonURLs[0]
        store.toggle(youtube)
        #expect(!store.isEnabled(youtube))
        store.switchProfile(to: b)
        #expect(store.isEnabled(youtube))
        store.switchProfile(to: a)
        #expect(!store.isEnabled(youtube))
    }

    @Test func migratesLegacyDisabledIntoFirstProfileOnly() {
        let suite = "tests.addons.disabled.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let youtube = AddonStore.defaultAddonURLs[0]
        defaults.set([youtube], forKey: AddonStore.disabledKey)
        let storage = InMemorySecretStorage(AddonStore.defaultAddonURLs)
        let a = UUID()
        let b = UUID()
        let first = AddonStore(storage: storage, legacyDefaults: makeDefaults(), defaults: defaults, profileID: a)
        #expect(!first.isEnabled(youtube))
        #expect(defaults.stringArray(forKey: AddonStore.disabledKey) == nil)
        first.switchProfile(to: b)
        #expect(first.isEnabled(youtube))
    }

    @Test func includedVersusInstallableAndDefaultsNotRemovable() {
        let personal = "https://streams.example"
        let storage = InMemorySecretStorage(AddonStore.defaultAddonURLs + [personal])
        let store = AddonStore(storage: storage, legacyDefaults: makeDefaults())
        #expect(store.includedURLs == AddonStore.defaultAddonURLs)
        #expect(store.personalURLs == [personal])
        #expect(store.personalAddonCount == 1)
        store.remove(AddonStore.defaultAddonURLs[0])
        #expect(store.urls.contains(AddonStore.defaultAddonURLs[0]))
        store.remove(personal)
        #expect(!store.urls.contains(personal))
        #expect(store.personalAddonCount == 0)
    }
}
