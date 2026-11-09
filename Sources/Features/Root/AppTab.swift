import Foundation

/// Top-level destinations, in rail order.
enum AppTab: CaseIterable, Hashable {
    case home, movies, series, myList, search, settings

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .movies: return "Films"
        case .series: return "Séries"
        case .myList: return "Ma liste"
        case .search: return "Recherche"
        case .settings: return "Réglages"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .series: return "tv"
        case .myList: return "plus.rectangle.on.rectangle"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}
