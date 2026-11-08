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
    
    public var isDebrid: Bool {
        let full = "\(name ?? "") \(title ?? "")"
        return full.contains("RD") || full.contains("Debrid") || full.contains("AD") || full.contains("PM") || full.contains("⚡️")
    }
    
    public var providerName: String {
        guard let name = name, !name.isEmpty else { return "Addon" }
        let firstLine = name.components(separatedBy: .newlines).first ?? name
        return firstLine
            .replacingOccurrences(of: "[RD+]", with: "")
            .replacingOccurrences(of: "[RD]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var resolution: String {
        let text = "\(name ?? "") \(title ?? "")"
        if text.localizedCaseInsensitiveContains("4k") || text.localizedCaseInsensitiveContains("2160p") {
            if text.localizedCaseInsensitiveContains("hdr") || text.localizedCaseInsensitiveContains("dv") || text.localizedCaseInsensitiveContains("vision") {
                return "4K HDR"
            }
            return "4K UHD"
        } else if text.localizedCaseInsensitiveContains("1080p") {
            return "1080p"
        } else if text.localizedCaseInsensitiveContains("720p") {
            return "720p"
        }
        return "HD"
    }
    
    public var hdrBadge: String? {
        let text = "\(name ?? "") \(title ?? "")".lowercased()
        if text.contains("dv") || text.contains("vision") {
            return "Dolby Vision"
        } else if text.contains("hdr10+") {
            return "HDR10+"
        } else if text.contains("hdr") {
            return "HDR"
        }
        return nil
    }
    
    public var audioBadge: String? {
        let text = "\(name ?? "") \(title ?? "")".lowercased()
        if text.contains("atmos") {
            return "Atmos"
        } else if text.contains("dts-hd") || text.contains("truehd") {
            return "TrueHD"
        } else if text.contains("5.1") {
            return "5.1"
        } else if text.contains("7.1") {
            return "7.1"
        }
        return nil
    }
    
    public var sizeInfo: String? {
        guard let title = title else { return nil }
        // Match 💾 12.3 GB or 12.3 GB / MB
        let patterns = ["([0-9]+(\\.[0-9]+)?\\s*(GB|MB|GiB|MiB))"]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range, in: title) {
                return String(title[range])
            }
        }
        return nil
    }
    
    public var seedersInfo: String? {
        guard let title = title else { return nil }
        if let regex = try? NSRegularExpression(pattern: "(👥|seeds?:?)\\s*([0-9]+)", options: .caseInsensitive),
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let range = Range(match.range(at: 2), in: title) {
            return String(title[range])
        }
        return nil
    }
    
    public var parsedTitle: String {
        if let title = title, !title.isEmpty {
            let lines = title.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return lines.first ?? title
        }
        return name ?? "Flux vidéo"
    }
}
