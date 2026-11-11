import XCTest
@testable import StremioTV

@MainActor
final class PersonDetailTests: XCTestCase {

    func testPersonCreditProperties() {
        let credit = PersonCredit(
            id: "tmdb:454",
            tmdbID: 454,
            title: "Inception",
            type: .movie,
            character: "Dom Cobb",
            releaseDate: "2010-07-16",
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            voteAverage: 8.8,
            popularity: 85.5
        )

        XCTAssertEqual(credit.releaseYear, "2010")
        XCTAssertEqual(credit.posterURL?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")

        let media = credit.toMediaItem()
        XCTAssertEqual(media.id, "tmdb:454")
        XCTAssertEqual(media.name, "Inception")
        XCTAssertEqual(media.type, .movie)
        XCTAssertEqual(media.releaseInfo, "2010")
        XCTAssertEqual(media.description, "Rôle : Dom Cobb")
        XCTAssertEqual(media.imdbRating, "8.8")
    }

    func testPersonDetailViewModelFiltering() async {
        let member = CastMember(id: "6193", name: "Leonardo DiCaprio")
        let movieCredit = PersonCredit(
            id: "tmdb:1",
            tmdbID: 1,
            title: "Titanic",
            type: .movie,
            character: "Jack Dawson",
            releaseDate: "1997-12-19",
            popularity: 90.0
        )
        let seriesCredit = PersonCredit(
            id: "tmdb:2",
            tmdbID: 2,
            title: "Growing Pains",
            type: .series,
            character: "Luke Brower",
            releaseDate: "1985-09-24",
            popularity: 20.0
        )

        let mockPerson = PersonDetail(
            id: "6193",
            name: "Leonardo DiCaprio",
            biography: "Acteur américain.",
            birthday: "1974-11-11",
            placeOfBirth: "Los Angeles",
            credits: [movieCredit, seriesCredit]
        )

        let mockService = MockPersonService(personDetail: mockPerson)
        let vm = PersonDetailViewModel(member: member, service: mockService)

        XCTAssertEqual(vm.state, .idle)
        await vm.loadIfNeeded()

        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.totalCount, 2)
        XCTAssertEqual(vm.movieCount, 1)
        XCTAssertEqual(vm.seriesCount, 1)

        // Filter: All
        vm.selectedFilter = .all
        XCTAssertEqual(vm.filteredCredits.count, 2)

        // Filter: Movies
        vm.selectedFilter = .movies
        XCTAssertEqual(vm.filteredCredits.count, 1)
        XCTAssertEqual(vm.filteredCredits.first?.title, "Titanic")

        // Filter: Series
        vm.selectedFilter = .series
        XCTAssertEqual(vm.filteredCredits.count, 1)
        XCTAssertEqual(vm.filteredCredits.first?.title, "Growing Pains")
    }

    func testPersonDetailViewModelInvalidID() async {
        let invalidMember = CastMember(id: "invalid-id", name: "Unknown")
        let vm = PersonDetailViewModel(member: invalidMember, service: MockPersonService(personDetail: nil))

        await vm.loadIfNeeded()
        XCTAssertTrue(vm.state.isFailure)
    }
}

private struct MockPersonService: StremioProviding {
    let personDetail: PersonDetail?

    func fetchCatalog(type: MediaType, genre: String?) async throws -> [MediaItem] { [] }
    func searchCatalog(type: MediaType, query: String) async throws -> [MediaItem] { [] }
    func fetchDetails(type: MediaType, id: String) async throws -> MediaDetail {
        fatalError("Not needed")
    }
    func fetchStreams(type: MediaType, id: String, addonBaseURLs: [String]) async -> [StreamItem] { [] }
    func fetchPerson(personID: Int, language: String) async -> PersonDetail? {
        personDetail
    }
}
