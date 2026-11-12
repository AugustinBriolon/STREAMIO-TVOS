import Foundation
import Testing
@testable import Loge

struct WatchProviderTests {
    @Test func prefersFlatrateThenRentAndDedupes() {
        let region: [String: Any] = [
            "flatrate": [
                ["provider_id": 8, "provider_name": "Netflix", "logo_path": "/netflix.png"],
                ["provider_id": 119, "provider_name": "Prime", "logo_path": "/prime.png"],
            ],
            "rent": [
                ["provider_id": 8, "provider_name": "Netflix", "logo_path": "/netflix.png"],
                ["provider_id": 2, "provider_name": "Apple TV", "logo_path": "/apple.png"],
            ],
        ]
        let picked = TMDBService.pickWatchProviders(from: region, limit: 8)
        #expect(picked.map(\.id) == [8, 119, 2])
        #expect(picked.first?.logoURL?.absoluteString == "https://image.tmdb.org/t/p/w92/netflix.png")
    }

    @Test func watchRegionFollowsMetadataLanguage() {
        #expect(TMDBService.watchRegion(for: "fr") == "FR")
        #expect(TMDBService.watchRegion(for: "en-US") == "US")
    }
}
