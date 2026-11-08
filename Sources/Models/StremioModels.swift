import Foundation

public struct CatalogResponse: Codable {
    public let metas: [MediaItem]
    
    public init(metas: [MediaItem]) {
        self.metas = metas
    }
}

public struct MediaItem: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let type: String
    public let poster: String?
    public let background: String?
    public let description: String?
    public let year: String?
    public let imdbRating: String?
    public let genres: [String]?
    
    public var posterURL: URL? {
        guard let poster = poster, let url = URL(string: poster) else { return nil }
        return url
    }
    
    public var backgroundURL: URL? {
        guard let background = background, let url = URL(string: background) else { return nil }
        return url
    }
}

public struct MetaDetailResponse: Codable {
    public let meta: MediaDetail
}

public struct MediaDetail: Codable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public let poster: String?
    public let background: String?
    public let description: String?
    public let year: String?
    public let imdbRating: String?
    public let genres: [String]?
    public let releaseInfo: String?
    public let runtime: String?
    public let cast: [String]?
    public let director: [String]?
    public let videos: [VideoItem]?
    
    public var posterURL: URL? {
        guard let poster = poster, let url = URL(string: poster) else { return nil }
        return url
    }
    
    public var backgroundURL: URL? {
        guard let background = background, let url = URL(string: background) else { return nil }
        return url
    }
}

public struct VideoItem: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let season: Int
    public let number: Int?
    public let episode: Int?
    public let overview: String?
    public let thumbnail: String?
    public let released: String?
    
    public var episodeNumber: Int {
        return number ?? episode ?? 1
    }
    
    public var displayTitle: String {
        let epName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let epName = epName, !epName.isEmpty {
            return "Épisode \(episodeNumber) : \(epName)"
        }
        return "Épisode \(episodeNumber)"
    }
}

public struct StreamsResponse: Codable {
    public let streams: [StreamItem]?
}

public struct StreamItem: Codable, Identifiable, Hashable {
    public var id: String {
        return url ?? (title ?? UUID().uuidString)
    }
    
    public let name: String?
    public let title: String?
    public let url: String?
    
    public var resolution: String {
        let text = "\(name ?? "") \(title ?? "")"
        if text.localizedCaseInsensitiveContains("4k") || text.localizedCaseInsensitiveContains("2160p") {
            return "4K"
        } else if text.localizedCaseInsensitiveContains("1080p") {
            return "1080p"
        } else if text.localizedCaseInsensitiveContains("720p") {
            return "720p"
        }
        return "HD"
    }
    
    public var parsedTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return name ?? "Flux vidéo"
    }
}
