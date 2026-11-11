import Testing
@testable import Loge

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

    @Test func availabilityDetectsAddonNoticesAndPlayableStreams() async {
        var service = StubService()
        let notice = StreamItem(name: "StreamFusion", title: "2 sources mais aucune qui passe vos filtres")
        service.streams["tt99"] = [notice]

        let unavailableModel = DetailViewModel(item: movie("tt99", "Model Citizen"), service: service)
        await unavailableModel.checkAvailability(addons: ["https://addon.test"], targetVideoID: nil, device: .all)
        #expect(unavailableModel.availability == .unavailable(notices: ["2 sources mais aucune qui passe vos filtres"], totalCount: 1))
        #expect(!unavailableModel.availability.hasPlayableStream)
        #expect(unavailableModel.prefetchedStreams(for: "tt99")?.count == 1)

        service.streams["tt100"] = [notice, stream("RD+", url: "https://cdn/movie.mkv")]
        let availableModel = DetailViewModel(item: movie("tt100", "Playable"), service: service)
        await availableModel.checkAvailability(addons: ["https://addon.test"], targetVideoID: nil, device: .all)
        #expect(availableModel.availability == .available(playableCount: 1, totalCount: 2))
        #expect(availableModel.availability.hasPlayableStream)

        await availableModel.checkAvailability(addons: [], targetVideoID: nil, device: .all)
        #expect(availableModel.availability == .noAddons)
    }
}

@MainActor
struct StreamsViewModelTests {
    @Test func filtersOutUnplayableEntriesByDefaultAndAllowsShowingAll() async {
        var service = StubService()
        let playable = stream("RD+", url: "https://cdn/ok.mp4")
        let torrent = stream("Torrentio", url: nil, infoHash: "abc")
        let notice = StreamItem(name: "StreamFusion", title: "2 sources mais aucune qui passe vos filtres")
        service.streams["tt1"] = [notice, torrent, playable]

        let model = StreamsViewModel(service: service)
        await model.load(type: .movie, videoID: "tt1", addons: ["https://addon.test"])

        #expect(model.playableCount == 1)
        #expect(model.displayedStreams.map(\.id) == [playable.id])
        #expect(model.noticeSummary == "2 sources mais aucune qui passe vos filtres")

        model.filter = .all
        #expect(model.displayedStreams.count == 3)
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

@MainActor
struct DetailBackdropTests {
    @Test func titlePageKeepsTheBackdropItOpenedWith() {
        let withImage = MediaItem(id: "tmdb:1", name: "A", type: .movie, background: "https://image.tmdb.org/t/p/w1280/a.jpg")
        #expect(DetailViewModel(item: withImage, service: StubService()).backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/a.jpg")
        let bare = MediaItem(id: "tt1", name: "B", type: .movie)
        #expect(DetailViewModel(item: bare, service: StubService()).backdropURL == bare.backgroundURL)
    }
}
