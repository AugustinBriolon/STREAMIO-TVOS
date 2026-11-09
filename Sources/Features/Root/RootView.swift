import SwiftUI

/// Sidebar navigation and the app-wide player presentation.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        @Bindable var playback = playback
        TabView {
            Tab("Accueil", systemImage: "house") { HomeView(scope: nil) }
            Tab("Films", systemImage: "film") { HomeView(scope: .movie) }
            Tab("Séries", systemImage: "tv") { HomeView(scope: .series) }
            Tab("Ma liste", systemImage: "plus.rectangle.on.rectangle") { MyListView() }
            Tab("Recherche", systemImage: "magnifyingglass", role: .search) { SearchView() }
            Tab("Réglages", systemImage: "gearshape") { SettingsView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay {
            if playback.isResolving {
                StateView(kind: .loading("Recherche du meilleur flux…"))
                    .background(.black.opacity(0.75))
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { playback.session != nil },
            set: { if !$0 { playback.close() } }
        )) {
            if let session = playback.session {
                PlayerView(session: session, playback: playback).ignoresSafeArea()
            }
        }
        .alert("Lecture impossible", isPresented: Binding(
            get: { playback.errorMessage != nil },
            set: { if !$0 { playback.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playback.errorMessage ?? "")
        }
    }
}
