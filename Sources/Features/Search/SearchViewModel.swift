import Foundation
import Observation

/// Debounced live search over movies and series; a newer query always wins.
@MainActor
@Observable
final class SearchViewModel {
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var movies: [MediaItem] = []
    private(set) var series: [MediaItem] = []
    private(set) var suggestions: [MediaItem] = []
    private(set) var state: LoadState = .idle

    @ObservationIgnored private let service: StremioProviding
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(service: StremioProviding = StremioService(), debounce: Duration = .milliseconds(400)) {
        self.service = service
        self.debounce = debounce
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasResults: Bool { !movies.isEmpty || !series.isEmpty }

    func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        suggestions = Array(((try? await service.fetchCatalog(type: .movie, genre: nil)) ?? []).prefix(30))
    }

    /// Exposed for tests; the UI goes through `query`.
    func waitForPendingSearch() async {
        await searchTask?.value
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = trimmedQuery
        guard !term.isEmpty else {
            movies = []
            series = []
            state = .idle
            return
        }
        searchTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await search(term)
        }
    }

    private func search(_ term: String) async {
        state = .loading
        async let movieResults = Result { try await service.searchCatalog(type: .movie, query: term) }
        async let seriesResults = Result { try await service.searchCatalog(type: .series, query: term) }
        let (foundMovies, foundSeries) = await (movieResults, seriesResults)
        guard !Task.isCancelled, term == trimmedQuery else { return }
        movies = (try? foundMovies.get()) ?? []
        series = (try? foundSeries.get()) ?? []
        if case .failure(let error) = foundMovies, case .failure = foundSeries {
            state = .failure(error)
        } else {
            state = .loaded
        }
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
