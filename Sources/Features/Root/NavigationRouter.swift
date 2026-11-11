import SwiftUI
import Observation

/// Coordinateur centralisé de navigation multi-onglets tvOS.
/// Maintient l'état des piles de navigation (NavigationPath) pour chaque onglet,
/// permet la détection de profondeur (`isAtRoot`) et implémente le contrat Apple HIG "Pop to Root".
@Observable @MainActor
final class NavigationRouter {
    var homePath = NavigationPath()
    var moviesPath = NavigationPath()
    var seriesPath = NavigationPath()
    var myListPath = NavigationPath()
    var searchPath = NavigationPath()

    init() {}

    /// Fournit une liaison bidirectionnelle vers le chemin de navigation d'un onglet.
    func path(for tab: AppTab) -> Binding<NavigationPath> {
        switch tab {
        case .home:
            return Binding(get: { self.homePath }, set: { self.homePath = $0 })
        case .movies:
            return Binding(get: { self.moviesPath }, set: { self.moviesPath = $0 })
        case .series:
            return Binding(get: { self.seriesPath }, set: { self.seriesPath = $0 })
        case .myList:
            return Binding(get: { self.myListPath }, set: { self.myListPath = $0 })
        case .search:
            return Binding(get: { self.searchPath }, set: { self.searchPath = $0 })
        case .settings, .profiles:
            return .constant(NavigationPath())
        }
    }

    /// Indique si l'onglet est sur son écran d'accueil (racine), sans fiche poussée.
    func isAtRoot(for tab: AppTab) -> Bool {
        switch tab {
        case .home: return homePath.isEmpty
        case .movies: return moviesPath.isEmpty
        case .series: return seriesPath.isEmpty
        case .myList: return myListPath.isEmpty
        case .search: return searchPath.isEmpty
        case .settings, .profiles: return true
        }
    }

    /// Dépile toute la pile de navigation de l'onglet pour revenir immédiatement à sa racine.
    func popToRoot(for tab: AppTab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .movies: moviesPath = NavigationPath()
        case .series: seriesPath = NavigationPath()
        case .myList: myListPath = NavigationPath()
        case .search: searchPath = NavigationPath()
        case .settings, .profiles: break
        }
    }
}
