import Foundation
import Testing
@testable import Loge

struct TrailerLanguageTests {
    @Test func prefersTrailerInMetadataLanguage() {
        let videos = [
            TMDBVideoItem(key: "enTrailer", type: "Trailer", iso_639_1: "en"),
            TMDBVideoItem(key: "frTrailer", type: "Trailer", iso_639_1: "fr"),
            TMDBVideoItem(key: "frTeaser", type: "Teaser", iso_639_1: "fr"),
        ]
        #expect(TMDBService.pickTrailerKey(from: videos, preferredLanguage: "fr") == "frTrailer")
        #expect(TMDBService.pickTrailerKey(from: videos, preferredLanguage: "en") == "enTrailer")
    }

    @Test func fallsBackToEnglishThenAny() {
        let videos = [
            TMDBVideoItem(key: "enTrailer", type: "Trailer", iso_639_1: "en"),
            TMDBVideoItem(key: "deTeaser", type: "Teaser", iso_639_1: "de"),
        ]
        #expect(TMDBService.pickTrailerKey(from: videos, preferredLanguage: "fr") == "enTrailer")
        #expect(TMDBService.pickTrailerKey(from: videos, preferredLanguage: "it") == "enTrailer")
    }

    @Test func demotesAutoDubNamedUploads() {
        let videos = [
            TMDBVideoItem(
                key: "autoFr",
                name: "Official Trailer (Auto-dubbed French)",
                type: "Trailer",
                official: true,
                iso_639_1: "fr"
            ),
            TMDBVideoItem(
                key: "realEn",
                name: "Official Trailer",
                type: "Trailer",
                official: true,
                iso_639_1: "en"
            ),
        ]
        #expect(TMDBService.pickTrailerKey(from: videos, preferredLanguage: "fr") == "realEn")
    }

    @Test func prefersOfficialVFNamedFrenchTrailer() {
        let videos = [
            TMDBVideoItem(key: "en", name: "Trailer", type: "Trailer", official: true, iso_639_1: "en"),
            TMDBVideoItem(key: "frVF", name: "Bande-annonce VF", type: "Trailer", official: true, iso_639_1: "fr"),
        ]
        #expect(TMDBService.pickTrailerKey(from: videos, preferredLanguage: "fr") == "frVF")
    }
}
