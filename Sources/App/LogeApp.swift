import SwiftUI

@main
struct LogeApp: App {
    @State private var profiles: ProfileStore
    @State private var library: LibraryStore
    @State private var addons: AddonStore
    @State private var playback: PlaybackCoordinator
    @State private var configServer: ConfigServer
    @State private var auth: AuthService
    @State private var syncEngine: CloudSyncEngine
    @State private var entitlements: EntitlementStore

    init() {
        // Enregistrement de la locale et des langues pour la dictée et le clavier système tvOS
        UserDefaults.standard.register(defaults: [
            "AppleLanguages": ["fr", "en"],
            "AppleLocale": "fr_FR"
        ])

        // Posters and backdrops are re-shown constantly while browsing rows; keep them on disk.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        let profiles = ProfileStore()
        let library = LibraryStore(profileID: profiles.activeID)
        _profiles = State(initialValue: profiles)
        let addons = AddonStore()
        _library = State(initialValue: library)
        _addons = State(initialValue: addons)
        _playback = State(initialValue: PlaybackCoordinator(service: StremioService(), addons: addons, library: library))
        _configServer = State(initialValue: ConfigServer(addons: addons))

        let auth = AuthService.shared
        _auth = State(initialValue: auth)
        let sync = CloudSyncEngine(auth: auth, profiles: profiles, library: library, addons: addons)
        _syncEngine = State(initialValue: sync)
        _entitlements = State(initialValue: EntitlementStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profiles)
                .environment(library)
                .environment(addons)
                .environment(playback)
                .environment(configServer)
                .environment(auth)
                .environment(syncEngine)
                .environment(entitlements)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
                .task {
                    // Synchronisation silencieuse au lancement si un compte est connecté
                    if auth.isAuthenticated {
                        await syncEngine.sync()
                    }
                    await entitlements.loadProducts()
                }
        }
    }
}
