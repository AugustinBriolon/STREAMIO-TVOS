import Foundation
@testable import Loge

struct StubError: Error {}

/// Canned network responses keyed by request.
struct StubService: StremioProviding {
    var catalogs: [String: [MediaItem]] = [:]
    var failingCatalogs: Set<String> = []
    var searchResults: [MediaType: [MediaItem]] = [:]
    var details: [String: MediaDetail] = [:]
    var streams: [String: [StreamItem]] = [:]

    static func catalogKey(_ type: MediaType, _ genre: String?) -> String { "\(type.rawValue)/\(genre ?? "top")" }

    func fetchCatalog(type: MediaType, genre: String?) async throws -> [MediaItem] {
        let key = Self.catalogKey(type, genre)
        if failingCatalogs.contains(key) || failingCatalogs.contains("*") { throw StubError() }
        return catalogs[key] ?? []
    }

    func searchCatalog(type: MediaType, query: String) async throws -> [MediaItem] {
        searchResults[type]?.filter { $0.name.localizedCaseInsensitiveContains(query) } ?? []
    }

    func fetchDetails(type: MediaType, id: String) async throws -> MediaDetail {
        guard let detail = details[id] else { throw StubError() }
        return detail
    }

    func fetchStreams(type: MediaType, id: String, addonBaseURLs: [String]) async -> [StreamItem] {
        streams[id] ?? []
    }
}

final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    var values: [String]?
    var failsOnSave = false

    init(_ values: [String]? = nil) { self.values = values }

    func load() -> [String]? { values }

    func save(_ values: [String]) -> Bool {
        guard !failsOnSave else { return false }
        self.values = values
        return true
    }
}

func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
}

/// Clock advancing one second per call, so update order is deterministic.
final class TestClock: @unchecked Sendable {
    private var current = Date(timeIntervalSince1970: 1_000_000)
    func now() -> Date {
        current = current.addingTimeInterval(1)
        return current
    }
}

func movie(_ id: String, _ name: String = "Film", background: String? = "https://img/bg", description: String? = "Synopsis", genres: [String]? = ["Action"]) -> MediaItem {
    MediaItem(id: id, name: name, type: .movie, poster: "https://img/p", background: background, description: description, genres: genres)
}

func show(_ id: String, _ name: String = "Série") -> MediaItem {
    MediaItem(id: id, name: name, type: .series, poster: "https://img/p", background: "https://img/bg", description: "Synopsis", genres: ["Drama"])
}

func episode(_ season: Int, _ number: Int, show id: String = "tt1") -> VideoItem {
    VideoItem(id: "\(id):\(season):\(number)", name: "Ep \(number)", season: season, number: number)
}

func stream(_ name: String, _ title: String = "", url: String? = "https://cdn/x.mp4", infoHash: String? = nil) -> StreamItem {
    StreamItem(name: name, title: title, url: url, infoHash: infoHash)
}
