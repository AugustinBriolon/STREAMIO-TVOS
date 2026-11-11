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
    var posterURL: URL? {
        if let poster, let url = URL(string: poster) { return url }
        if id.hasPrefix("tt") {
            return URL(string: "https://images.metahub.space/poster/medium/\(id)/img")
        }
        return nil
    }
    var backgroundURL: URL? {
        if let background, let url = URL(string: background) { return url }
        if id.hasPrefix("tt") {
            return URL(string: "https://images.metahub.space/background/medium/\(id)/img")
        }
        return posterURL
    }

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

public struct CastMember: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let character: String?
    public let photo: String?

    public init(id: String, name: String, character: String? = nil, photo: String? = nil) {
        self.id = id
        self.name = name
        self.character = character
        self.photo = photo
    }

    public var photoURL: URL? { photo.flatMap(URL.init(string:)) }
}

/// Modèle pour la fiche complète d'une personnalité / acteur avec filmographie
public struct PersonDetail: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let biography: String?
    public let profilePath: String?
    public let birthday: String?
    public let placeOfBirth: String?
    public let credits: [PersonCredit]

    public init(
        id: String,
        name: String,
        biography: String? = nil,
        profilePath: String? = nil,
        birthday: String? = nil,
        placeOfBirth: String? = nil,
        credits: [PersonCredit] = []
    ) {
        self.id = id
        self.name = name
        self.biography = biography
        self.profilePath = profilePath
        self.birthday = birthday
        self.placeOfBirth = placeOfBirth
        self.credits = credits
    }

    public var photoURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300_and_h450_face\(profilePath)")
    }
}

/// Crédit d'apparition d'un acteur dans un film ou une série
public struct PersonCredit: Identifiable, Hashable, Sendable {
    public let id: String
    public let tmdbID: Int
    public let title: String
    public let type: MediaType
    public let character: String?
    public let releaseDate: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let popularity: Double?

    public init(
        id: String,
        tmdbID: Int,
        title: String,
        type: MediaType,
        character: String? = nil,
        releaseDate: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        voteAverage: Double? = nil,
        popularity: Double? = nil
    ) {
        self.id = id
        self.tmdbID = tmdbID
        self.title = title
        self.type = type
        self.character = character
        self.releaseDate = releaseDate
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.popularity = popularity
    }

    public var releaseYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    public var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    public func toMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            name: title,
            type: type,
            poster: posterURL?.absoluteString,
            background: backdropPath.map { "https://image.tmdb.org/t/p/w1280\($0)" },
            logo: nil,
            description: character.map { "Rôle : \($0)" },
            releaseInfo: releaseYear,
            runtime: nil,
            imdbRating: voteAverage.map { String(format: "%.1f", $0) },
            genres: nil
        )
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
    public let castMembers: [CastMember]?

    public init(
        id: String, name: String, type: MediaType,
        poster: String? = nil, background: String? = nil, logo: String? = nil,
        description: String? = nil, releaseInfo: String? = nil, runtime: String? = nil,
        imdbRating: String? = nil, genres: [String]? = nil,
        cast: [String]? = nil, director: [String]? = nil, videos: [VideoItem]? = nil,
        castMembers: [CastMember]? = nil
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
        self.castMembers = castMembers
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
