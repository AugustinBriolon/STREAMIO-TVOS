import SwiftUI

public struct RootView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            HomeCatalogView(type: "movie", title: "Films populaires")
                .tabItem {
                    Label("Films", systemImage: "film")
                }
            
            HomeCatalogView(type: "series", title: "Séries populaires")
                .tabItem {
                    Label("Séries", systemImage: "tv")
                }
            
            SearchCatalogView()
                .tabItem {
                    Label("Recherche", systemImage: "magnifyingglass")
                }
            
            SettingsCatalogView()
                .tabItem {
                    Label("Paramètres", systemImage: "gear")
                }
        }
        .onAppear {
            ConfigServer.shared.start()
        }
    }
}
