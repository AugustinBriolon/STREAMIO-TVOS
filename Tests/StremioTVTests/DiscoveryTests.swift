import Testing
import Foundation
@testable import StremioTV

@MainActor
struct DiscoveryTests {
    @Test func brandHubsHaveValidConfiguration() {
        let allHubs = BrandHub.moviePlatforms + BrandHub.movieStudios + BrandHub.seriesPlatforms + BrandHub.seriesNetworks
        let ids = allHubs.map(\.id)
        #expect(Set(ids).count == ids.count, "BrandHub IDs must be unique")

        for hub in allHubs {
            #expect(!hub.name.isEmpty)
            #expect(!hub.subtitle.isEmpty)
            #expect(!hub.systemSymbol.isEmpty)
            #expect(hub.accentColorHex.hasPrefix("#"))
            if hub.category == .platform {
                #expect(hub.logoURL != nil, "Platforms must provide a logoURL")
            }
        }
    }

    @Test func sagasHaveValidCuratedIDs() {
        #expect(!SagaCollection.curatedCollectionIDs.isEmpty)
        #expect(Set(SagaCollection.curatedCollectionIDs).count == SagaCollection.curatedCollectionIDs.count)
        let films = ["1977", "2019", "1980"].enumerated().map { MediaItem(id: "tmdb:\($0.offset)", name: "F", type: .movie, releaseInfo: $0.element) }
        let starWars = SagaCollection(id: "collection:10", tmdbCollectionID: 10, name: "Star Wars - Saga", overview: nil,
                                      posterPath: nil, backdropPath: "/b.jpg", partsCount: 3, parts: films)
        #expect(starWars.displayName == "Star Wars")
        #expect(starWars.yearSpan == "1977–2019")
        #expect(starWars.accentColorHex == "#FFE81F")
        #expect(starWars.backdropItem.background == "https://image.tmdb.org/t/p/w1280/b.jpg")
        let unknown = SagaCollection(id: "collection:1", tmdbCollectionID: 1, name: "Dune Collection", overview: nil,
                                     posterPath: nil, backdropPath: nil, partsCount: 0)
        #expect(unknown.displayName == "Dune")
        #expect(unknown.accentColorHex == nil)
        #expect(unknown.yearSpan == nil)
        let sample = SagaCollection(
            id: "collection:10",
            tmdbCollectionID: 10,
            name: "Star Wars",
            overview: "A long time ago...",
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            partsCount: 9,
            parts: []
        )
        #expect(sample.backdropURL?.absoluteString.contains("backdrop.jpg") == true)
        #expect(sample.posterURL?.absoluteString.contains("poster.jpg") == true)
    }

    @Test func awardCategoriesAreConfigured() {
        #expect(AwardCategory.movieAwards.count == 4)
        #expect(AwardCategory.seriesAwards.count == 3)

        for award in AwardCategory.movieAwards + AwardCategory.seriesAwards {
            #expect(!award.badge.isEmpty)
            #expect(!award.tmdbIDs.isEmpty)
        }
    }

    @Test func awardsServiceLoadsHistoricalEditions() {
        let service = AwardsService.shared
        #expect(!service.ceremonies.isEmpty)

        // Oscars
        let oscarYears = service.availableYears(for: "oscars")
        #expect(oscarYears.contains(2026))
        #expect(oscarYears.contains(2024))
        #expect(oscarYears.count >= 80)

        // Emmys
        let emmyYears = service.availableYears(for: "emmys")
        #expect(emmyYears.contains(2026))
        #expect(emmyYears.contains(2024))
        #expect(emmyYears.count >= 50)

        // Golden Globes
        let ggYears = service.availableYears(for: "golden-globes")
        #expect(ggYears.contains(2026))
        #expect(ggYears.count >= 70)

        // Categories & Winners
        let oscarCats2026 = service.categories(for: "oscars", year: 2026)
        #expect(!oscarCats2026.isEmpty)
        let bestPicture = oscarCats2026.first { $0.category.contains("Film") }
        #expect(bestPicture != nil)
        #expect(bestPicture?.winner != nil)
        #expect(!bestPicture!.nonWinners.isEmpty)

        // Historical winners subpage test
        let historicalOscars = service.historicalWinners(for: "oscars", matching: "Meilleur Film")
        #expect(!historicalOscars.isEmpty)
        #expect(historicalOscars.count >= 50)
        #expect(historicalOscars.first?.nominee.won == true)
    }

    @Test func homeViewModelExposesDiscoveryHubs() {
        let movieModel = HomeViewModel(scope: .movie)
        #expect(!movieModel.moviePlatforms.isEmpty)
        #expect(!movieModel.movieStudios.isEmpty)

        let seriesModel = HomeViewModel(scope: .series)
        #expect(!seriesModel.seriesPlatforms.isEmpty)
        #expect(!seriesModel.seriesNetworks.isEmpty)
    }

    @Test func awardsServiceBuildsShowcaseAndDistinctions() {
        let service = AwardsService.shared

        let awardedMovies = service.awardedShowcase(for: .movie, limit: 20)
        #expect(!awardedMovies.isEmpty)
        #expect(Set(awardedMovies.map(\.id)).count == awardedMovies.count, "Showcase movies must be deduplicated")
        #expect(awardedMovies.allSatisfy { $0.primaryDistinction.won && $0.item.posterURL != nil })

        let awardedSeries = service.awardedShowcase(for: .series, limit: 20)
        #expect(!awardedSeries.isEmpty)
        #expect(Set(awardedSeries.map(\.id)).count == awardedSeries.count, "Showcase series must be deduplicated")
        #expect(awardedSeries.allSatisfy { $0.primaryDistinction.won && $0.item.posterURL != nil })

        let firstMovie = awardedMovies[0].item
        let movieDistinctions = service.distinctions(for: firstMovie)
        #expect(!movieDistinctions.isEmpty)
        #expect(movieDistinctions.contains { $0.won })
    }
}
