import Foundation
import Observation

/// A catalog request rendered as one row.
struct CatalogSpec: Hashable {
    let title: String
    let type: MediaType
    let genre: String?
}

struct Shelf: Identifiable, Equatable {
    let title: String
    let items: [MediaItem]
    var id: String { title }
}

@MainActor
@Observable
final class HomeViewModel {
    let scope: MediaType?
    private(set) var state: LoadState = .idle
    private(set) var billboard: MediaItem?
    private(set) var top10: [MediaItem] = []
    private(set) var shelves: [Shelf] = []

    @ObservationIgnored private let service: StremioProviding
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(scope: MediaType?, service: StremioProviding = StremioService()) {
        self.scope = scope
        self.service = service
    }

    var top10Title: String {
        switch scope {
        case .series: return "Top 10 des séries aujourd'hui"
        case .movie, nil: return "Top 10 des films aujourd'hui"
        }
    }

    /// Catalogs load once per session; switching tabs does not refetch.
    /// The load runs in a task owned by the model: tvOS tab views appear/disappear at launch and
    /// would otherwise cancel the requests half-way.
    func loadIfNeeded() async {
        if state == .idle { loadTask = Task { await load() } }
        await loadTask?.value
    }

    func load() async {
        state = .loading
        let plan = Self.plan(for: scope)
        let specs = [plan.top] + plan.rows
        let results = await withTaskGroup(of: (Int, Result<[MediaItem], Error>).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask { [service] in
                    do { return (index, .success(try await service.fetchCatalog(type: spec.type, genre: spec.genre))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var collected = [Result<[MediaItem], Error>?](repeating: nil, count: specs.count)
            for await (index, result) in group { collected[index] = result }
            return collected.compactMap { $0 }
        }

        let lists = results.map { (try? $0.get()) ?? [] }
        guard lists.contains(where: { !$0.isEmpty }) else {
            let firstError = results.compactMap { if case .failure(let error) = $0 { return error } else { return nil } }.first
            state = firstError.map(LoadState.failure) ?? .failed("Catalogue indisponible.")
            return
        }

        let top = lists[0]
        top10 = Array(top.prefix(10))
        var rows: [Shelf] = []
        if top.count > 10 { rows.append(Shelf(title: plan.trendingTitle, items: Array(top.dropFirst(10)))) }
        rows += zip(plan.rows, lists.dropFirst())
            .filter { !$0.1.isEmpty }
            .map { Shelf(title: $0.0.title, items: $0.1) }
        shelves = rows
        billboard = Self.pickBillboard(from: top.isEmpty ? rows.first?.items ?? [] : top)
        state = .loaded
    }

    /// The most popular title that has artwork and a synopsis to show.
    static func pickBillboard(from items: [MediaItem]) -> MediaItem? {
        items.first { $0.background != nil && !($0.description ?? "").isEmpty } ?? items.first
    }

    static func plan(for scope: MediaType?) -> (top: CatalogSpec, trendingTitle: String, rows: [CatalogSpec]) {
        switch scope {
        case nil:
            return (CatalogSpec(title: "Top 10", type: .movie, genre: nil), "Films tendance", [
                CatalogSpec(title: "Séries populaires", type: .series, genre: nil),
                CatalogSpec(title: "Films d'action", type: .movie, genre: "Action"),
                CatalogSpec(title: "Séries comiques", type: .series, genre: "Comedy"),
                CatalogSpec(title: "Science-fiction", type: .movie, genre: "Sci-Fi"),
                CatalogSpec(title: "Polars et enquêtes", type: .series, genre: "Crime"),
                CatalogSpec(title: "Animation", type: .movie, genre: "Animation"),
                CatalogSpec(title: "Documentaires", type: .series, genre: "Documentary"),
            ])
        case .movie:
            return (CatalogSpec(title: "Top 10", type: .movie, genre: nil), "Films populaires", [
                CatalogSpec(title: "Action", type: .movie, genre: "Action"),
                CatalogSpec(title: "Aventure", type: .movie, genre: "Adventure"),
                CatalogSpec(title: "Comédies", type: .movie, genre: "Comedy"),
                CatalogSpec(title: "Science-fiction", type: .movie, genre: "Sci-Fi"),
                CatalogSpec(title: "Thrillers", type: .movie, genre: "Thriller"),
                CatalogSpec(title: "Horreur", type: .movie, genre: "Horror"),
                CatalogSpec(title: "Animation", type: .movie, genre: "Animation"),
                CatalogSpec(title: "Drames", type: .movie, genre: "Drama"),
            ])
        case .series:
            return (CatalogSpec(title: "Top 10", type: .series, genre: nil), "Séries populaires", [
                CatalogSpec(title: "Drames", type: .series, genre: "Drama"),
                CatalogSpec(title: "Comédies", type: .series, genre: "Comedy"),
                CatalogSpec(title: "Polars et enquêtes", type: .series, genre: "Crime"),
                CatalogSpec(title: "Science-fiction", type: .series, genre: "Sci-Fi"),
                CatalogSpec(title: "Animation", type: .series, genre: "Animation"),
                CatalogSpec(title: "Documentaires", type: .series, genre: "Documentary"),
                CatalogSpec(title: "Télé-réalité", type: .series, genre: "Reality-TV"),
            ])
        }
    }
}
