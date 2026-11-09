import Testing
@testable import StremioTV

@MainActor
struct HomeViewModelTests {
    @Test func buildsTop10TrendingAndGenreRows() async {
        var service = StubService()
        service.catalogs["movie/top"] = (0..<14).map { movie("m\($0)", background: $0 == 0 ? nil : "https://bg") }
        service.catalogs["movie/Action"] = [movie("a1")]
        let model = HomeViewModel(scope: .movie, service: service)
        await model.loadIfNeeded()
        #expect(model.state == .loaded)
        #expect(model.top10.count == 10)
        #expect(model.billboard?.id == "m1")
        #expect(model.shelves.map(\.title) == ["Films populaires", "Action"])
    }

    @Test func failsOnlyWhenEverythingFails() async {
        var service = StubService()
        service.failingCatalogs = ["*"]
        let model = HomeViewModel(scope: .series, service: service)
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failure, got \(model.state)")
            return
        }
    }

    @Test func usesValidCinemetaGenres() {
        let valid: Set<String> = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama",
                                  "Horror", "Sci-Fi", "Thriller", "Reality-TV"]
        for scope in [nil, MediaType.movie, .series] {
            for spec in HomeViewModel.plan(for: scope).rows {
                #expect(spec.genre.map(valid.contains) ?? true, "\(spec.genre ?? "")")
            }
        }
    }
}

@MainActor
struct DetailViewModelTests {
    @Test func opensResumeSeasonAndOrdersSpecialsLast() async {
        var service = StubService()
        service.details["tt1"] = MediaDetail(id: "tt1", name: "S", type: .series, genres: ["Drama"],
                                             videos: [episode(0, 1), episode(1, 1), episode(2, 2), episode(2, 1)])
        service.catalogs["series/Drama"] = [show("tt1"), show("tt2")]
        let model = DetailViewModel(item: show("tt1"), service: service)
        await model.loadIfNeeded(resumeSeason: 2)
        #expect(model.seasons == [1, 2, 0])
        #expect(model.selectedSeason == 2)
        #expect(model.episodesInSelectedSeason.map(\.episodeNumber) == [1, 2])
        #expect(model.similar.map(\.id) == ["tt2"])
        #expect(DetailViewModel.seasonLabel(0) == "Spéciaux")
    }
}

@MainActor
struct SearchViewModelTests {
    @Test func searchesBothTypesAndClearsOnEmptyQuery() async {
        var service = StubService()
        service.searchResults = [.movie: [movie("m", "Dune")], .series: [show("s", "Dune: Prophecy"), show("x", "Other")]]
        let model = SearchViewModel(service: service, debounce: .zero)
        model.query = "dune"
        await model.waitForPendingSearch()
        #expect(model.movies.map(\.id) == ["m"])
        #expect(model.series.map(\.id) == ["s"])
        model.query = "  "
        #expect(!model.hasResults)
        #expect(model.state == .idle)
    }

    @Test func newerQueryWins() async {
        var service = StubService()
        service.searchResults = [.movie: [movie("1", "Alien"), movie("2", "Aliens")]]
        let model = SearchViewModel(service: service, debounce: .milliseconds(50))
        model.query = "alien"
        model.query = "aliens"
        await model.waitForPendingSearch()
        #expect(model.movies.map(\.id) == ["2"])
    }
}

@MainActor
struct CancellationTests {
    @Test func cancellingTheViewTaskDoesNotAbortTheLoad() async {
        var service = StubService()
        service.catalogs["movie/top"] = [movie("m1")]
        let model = HomeViewModel(scope: .movie, service: service)
        let viewTask = Task { await model.loadIfNeeded() }
        viewTask.cancel()
        await viewTask.value
        await model.loadIfNeeded()
        #expect(model.state == .loaded)
        #expect(model.top10.map(\.id) == ["m1"])
    }
}
