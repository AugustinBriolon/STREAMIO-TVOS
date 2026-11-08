import SwiftUI

public struct RootView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            HomeCatalogView(type: "movie", title: "Films populaires")
                .tabItem {
                    Label("Films", systemImage: "film.stack")
                }
            
            HomeCatalogView(type: "series", title: "Séries populaires")
                .tabItem {
                    Label("Séries", systemImage: "tv.inset.filled")
                }
            
            SearchCatalogView()
                .tabItem {
                    Label("Recherche", systemImage: "magnifyingglass")
                }
            
            SettingsCatalogView()
                .tabItem {
                    Label("Paramètres", systemImage: "gearshape.fill")
                }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ConfigServer.shared.start()
        }
    }
}