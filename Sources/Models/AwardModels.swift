import Foundation
import SwiftUI

/// Informations signalétiques d'une grande cérémonie ou d'un festival.
public struct AwardCeremonyInfo: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let badge: String
    public let subtitle: String
    public let emblemName: String
    public let accentColorHex: String
    public let mediaType: String
    public let availableYears: [Int]

    public var accentColor: Color {
        Color(hex: accentColorHex)
    }

    public var systemSymbol: String {
        switch id {
        case "oscars": return "trophy.fill"
        case "cannes": return "crown.fill"
        case "emmys": return "sparkles"
        case "golden-globes": return "globe.americas.fill"
        case "cesar": return "medal.fill"
        default: return "star.fill"
        }
    }
}

/// Œuvre ou personne nominée à une cérémonie.
public struct AwardNomineeItem: Identifiable, Codable, Hashable {
    public var id: String {
        "\(title)_\(nominee ?? "")_\(imdbId ?? "")"
    }
    public let title: String
    public let nominee: String?
    public let won: Bool
    public let imdbId: String?
    public let tmdbId: Int?
    public let mediaType: String
    public let posterPath: String?

    public var resolvedMediaType: MediaType {
        mediaType == "series" ? .series : .movie
    }

    /// Convertit en MediaItem pour la navigation vers `DetailView`.
    public func toMediaItem(category: String, year: Int) -> MediaItem {
        let streamId: String
        if let imdb = imdbId, !imdb.isEmpty, imdb.hasPrefix("tt") {
            streamId = imdb
        } else if let tmdb = tmdbId, tmdb > 0 {
            streamId = "tmdb:\(tmdb)"
        } else {
            streamId = "tmdb:0"
        }

        let posterString: String? = posterPath.flatMap { path in
            if path.hasPrefix("http") {
                return path
            } else {
                return "https://image.tmdb.org/t/p/w500\(path)"
            }
        }

        return MediaItem(
            id: streamId,
            name: title,
            type: resolvedMediaType,
            poster: posterString,
            background: nil,
            logo: nil,
            description: nominee != nil ? "Nomination / Lauréat : \(nominee!) (\(category) \(year))" : "\(category) \(year)",
            releaseInfo: "\(year)",
            runtime: nil,
            imdbRating: won ? "🏆 Gagnant" : "Nommé",
            genres: [category, "\(year)"]
        )
    }
}

/// Groupe représentant une sous-catégorie d'une édition donnée (ex: "Meilleure Série Dramatique").
public struct AwardCategoryGroup: Identifiable, Hashable {
    public var id: String { category }
    public let category: String
    public let nominees: [AwardNomineeItem]

    public var winner: AwardNomineeItem? {
        nominees.first(where: { $0.won })
    }

    public var nonWinners: [AwardNomineeItem] {
        nominees.filter { !$0.won }
    }
}

/// Distinction reçue par une œuvre lors d'une cérémonie (utilisée dans DetailView et la section Primés).
public struct AwardDistinction: Identifiable, Hashable, Sendable {
    public var id: String { "\(ceremonyId)-\(year)-\(category)-\(won)" }
    public let ceremonyId: String
    public let ceremonyName: String
    public let ceremonyBadge: String
    public let accentColorHex: String
    public let year: Int
    public let category: String
    public let won: Bool
    public let nominee: String?

    public var accentColor: Color {
        Color(hex: accentColorHex)
    }

    public var shortCeremonyLabel: String {
        switch ceremonyId {
        case "oscars": return "Oscar"
        case "cannes": return category.lowercased().contains("palme") ? "Palme d'Or" : "Cannes"
        case "cesar": return "César"
        case "emmys": return "Emmy"
        case "golden-globes": return "Golden Globe"
        default: return ceremonyName
        }
    }
}

/// Œuvre primée mise en avant dans les rangées "Films primés" / "Séries primées".
public struct AwardedMediaEntry: Identifiable, Hashable, Sendable {
    public var id: String { item.id }
    public let item: MediaItem
    public let primaryDistinction: AwardDistinction
    public let totalWins: Int
    public let totalNominations: Int
}

/// Payload complet du fichier AwardsData.json.
struct AwardsPayload: Codable {
    let ceremonies: [AwardCeremonyInfo]
    let editions: [String: [String: [String: [AwardNomineeItem]]]]
}
