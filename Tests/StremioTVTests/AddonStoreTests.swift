import Foundation
import Testing
@testable import StremioTV

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
}
