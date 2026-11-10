import SwiftUI

@main
struct StremioTVApp: App {
    @State private var profiles: ProfileStore
    @State private var library: LibraryStore
    @State private var addons: AddonStore
    @State private var playback: PlaybackCoordinator
    @State private var configServer: ConfigServer

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profiles)
                .environment(library)
                .environment(addons)
                .environment(playback)
                .environment(configServer)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
        }
    }
}
