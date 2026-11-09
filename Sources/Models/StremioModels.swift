import Foundation

public enum MediaType: String, Codable, CaseIterable, Hashable, Sendable {
    case movie
    case series
}

/// Shared artwork resolution for catalog and detail metas.
public protocol ArtworkProviding {
    var id: String { get }
    var poster: String? { get }
    var background: String? { get }
    var logo: String? { get }
}

public extension ArtworkProviding {
    var posterURL: URL? { poster.flatMap(URL.init(string:)) }
    var backgroundURL: URL? { background.flatMap(URL.init(string:)) ?? posterURL }

    /// Cinemeta logos live on metahub; derive one for IMDb ids when the meta has none.
    var logoURL: URL? {
        if let logo, let url = URL(string: logo) { return url }
        guard id.hasPrefix("tt") else { return nil }
        return URL(string: "https://images.metahub.space/logo/medium/\(id)/img")
    }
}

public struct CatalogResponse: Codable {
    public let metas: [MediaItem]
}

public struct MediaItem: Codable, Identifiable, Hashable, Sendable, ArtworkProviding {
    public let id: String
    public let name: String
    public let type: MediaType
    public let poster: String?
    public let background: String?
    public let logo: String?
    public let description: String?
    public let releaseInfo: String?
    public let runtime: String?
    public let imdbRating: String?
    public let genres: [String]?

    public init(
        id: String, name: String, type: MediaType,
        poster: String? = nil, background: String? = nil, logo: String? = nil,
        description: String? = nil, releaseInfo: String? = nil, runtime: String? = nil,
        imdbRating: String? = nil, genres: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.poster = poster
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.runtime = runtime
        self.imdbRating = imdbRating
        self.genres = genres
    }

    /// Year, runtime and genres for the "meta line" under a title. Rating is rendered separately.
    public var metaComponents: [String] {
        [releaseInfo, runtime, genres?.prefix(2).joined(separator: ", ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    public var displayRating: String? {
        guard let imdbRating, !imdbRating.isEmpty, imdbRating != "0" else { return nil }
        return imdbRating
    }
}

public struct MetaDetailResponse: Codable {
    public let meta: MediaDetail
}

public struct MediaDetail: Codable, Identifiable, Sendable, ArtworkProviding {
    public let id: String
    public let name: String
    public let type: MediaType
    public let poster: String?
    public let background: String?
    public let logo: String?
    public let description: String?
    public let releaseInfo: String?
    public let runtime: String?
    public let imdbRating: String?
    public let genres: [String]?
    public let cast: [String]?
    public let director: [String]?
    public let videos: [VideoItem]?

    public init(
        id: String, name: String, type: MediaType,
        poster: String? = nil, background: String? = nil, logo: String? = nil,
        description: String? = nil, releaseInfo: String? = nil, runtime: String? = nil,
        imdbRating: String? = nil, genres: [String]? = nil,
        cast: [String]? = nil, director: [String]? = nil, videos: [VideoItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.poster = poster
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.runtime = runtime
        self.imdbRating = imdbRating
        self.genres = genres
        self.cast = cast
        self.director = director
        self.videos = videos
    }

    /// Catalog-level summary, used for library persistence and navigation.
    public var summary: MediaItem {
        MediaItem(
            id: id, name: name, type: type, poster: poster, background: background, logo: logo,
            description: description, releaseInfo: releaseInfo, runtime: runtime,
            imdbRating: imdbRating, genres: genres
        )
    }
}

public struct VideoItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let season: Int
    public let number: Int?
    public let episode: Int?
    public let overview: String?
    public let thumbnail: String?
    public let released: String?

    public init(
        id: String, name: String? = nil, season: Int, number: Int? = nil, episode: Int? = nil,
        overview: String? = nil, thumbnail: String? = nil, released: String? = nil
    ) {
        self.id = id
        self.name = name
        self.season = season
        self.number = number
        self.episode = episode
        self.overview = overview
        self.thumbnail = thumbnail
        self.released = released
    }

    public var episodeNumber: Int { number ?? episode ?? 1 }

    public var thumbnailURL: URL? { thumbnail.flatMap(URL.init(string:)) }

    public var cleanName: String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public var displayTitle: String {
        if let cleanName { return "Épisode \(episodeNumber) : \(cleanName)" }
        return "Épisode \(episodeNumber)"
    }

    /// Short code such as "S1:É3".
    public var code: String { "S\(season):É\(episodeNumber)" }
}

public extension Array where Element == VideoItem {
    /// Episodes in watch order; specials (season 0) go last.
    var inWatchOrder: [VideoItem] {
        sorted { lhs, rhs in
            let lhsSeason = lhs.season == 0 ? Int.max : lhs.season
            let rhsSeason = rhs.season == 0 ? Int.max : rhs.season
            if lhsSeason != rhsSeason { return lhsSeason < rhsSeason }
            return lhs.episodeNumber < rhs.episodeNumber
        }
    }

    /// Next regular episode after `video`, never jumping into specials.
    func episode(after video: VideoItem) -> VideoItem? {
        let ordered = inWatchOrder.filter { $0.season != 0 }
        guard let index = ordered.firstIndex(where: { $0.id == video.id }) else { return nil }
        let next = ordered.index(after: index)
        return next < ordered.endIndex ? ordered[next] : nil
    }

    /// First regular episode, or the first special when the show only has specials.
    var firstEpisode: VideoItem? {
        inWatchOrder.first { $0.season != 0 } ?? inWatchOrder.first
    }
}
