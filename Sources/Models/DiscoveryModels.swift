import Foundation

/// Modèle pour les hubs interactifs de studios et de plateformes de streaming.
public struct BrandHub: Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, Sendable {
        case studio
        case network
        case platform
    }

    public enum QuerySource: Hashable, Sendable {
        case company(Int)
        case network(Int)
        case watchProvider(Int, region: String = "FR")
    }

    public let id: String
    public let name: String
    public let subtitle: String
    public let category: Category
    public let querySource: QuerySource
    public let type: MediaType
    public let accentColorHex: String
    public let systemSymbol: String
    public let logoPath: String?

    public init(
        id: String,
        name: String,
        subtitle: String,
        category: Category,
        querySource: QuerySource,
        type: MediaType,
        accentColorHex: String,
        systemSymbol: String,
        logoPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.querySource = querySource
        self.type = type
        self.accentColorHex = accentColorHex
        self.systemSymbol = systemSymbol
        self.logoPath = logoPath
    }

    public var logoURL: URL? {
        guard let logoPath else { return nil }
        if logoPath.hasPrefix("http") { return URL(string: logoPath) }
        return URL(string: "https://image.tmdb.org/t/p/original\(logoPath)")
    }

    // MARK: - Sélections Prédéfinies

    /// Plateformes de streaming pour les films (logos officiels TMDB)
    public static let moviePlatforms: [BrandHub] = [
        BrandHub(id: "netflix-movies", name: "Netflix", subtitle: "Films & créations originales", category: .platform, querySource: .watchProvider(8), type: .movie, accentColorHex: "#E50914", systemSymbol: "play.tv.fill", logoPath: "/rK1KljqmbvO9HQa1PBFLILWah72.png"),
        BrandHub(id: "appletv-movies", name: "Apple TV+", subtitle: "Cinéma Apple Original", category: .platform, querySource: .watchProvider(350), type: .movie, accentColorHex: "#FFFFFF", systemSymbol: "apple.logo", logoPath: "/9icYBfYFcwgCbky5VdGUIKJ4C5i.png"),
        BrandHub(id: "disney-movies", name: "Disney+", subtitle: "Disney, Pixar, Marvel, Star Wars", category: .platform, querySource: .watchProvider(337), type: .movie, accentColorHex: "#113CCF", systemSymbol: "sparkles.tv.fill", logoPath: "/5eZ872CghnHFLB1j8grszbrx0dx.png"),
        BrandHub(id: "prime-movies", name: "Prime Video", subtitle: "Amazon MGM Studios", category: .platform, querySource: .watchProvider(119), type: .movie, accentColorHex: "#00A8E1", systemSymbol: "play.rectangle.fill", logoPath: "/gMZdpavHmxFNnLpMHwVxfqeux2g.png"),
        BrandHub(id: "max-movies", name: "Max", subtitle: "Warner Bros. & blockbusters", category: .platform, querySource: .watchProvider(1899), type: .movie, accentColorHex: "#002BE7", systemSymbol: "tv.fill", logoPath: "/skypuy7SXuugIQeYg0IglmzoKaS.png"),
        BrandHub(id: "canal-movies", name: "Canal+", subtitle: "Le grand cinéma récent", category: .platform, querySource: .watchProvider(381), type: .movie, accentColorHex: "#000000", systemSymbol: "film.fill", logoPath: "/gliWKhLJVdm7QwL1braBCRko5dx.png"),
        BrandHub(id: "paramount-movies", name: "Paramount+", subtitle: "Montagne de divertissement", category: .platform, querySource: .watchProvider(531), type: .movie, accentColorHex: "#0064FF", systemSymbol: "mountain.2.fill", logoPath: "/pkx3klJlwW5JdtaulvDx6hDNtch.png")
    ]

    /// Studios de cinéma emblématiques
    public static let movieStudios: [BrandHub] = [
        BrandHub(id: "a24-movies", name: "A24", subtitle: "Cinéma d'auteur & indépendant", category: .studio, querySource: .company(41077), type: .movie, accentColorHex: "#E5A93C", systemSymbol: "star.fill", logoPath: "/1ZXsGaFPgrgS6ZZGS37AqD5uU12.png"),
        BrandHub(id: "warner-movies", name: "Warner Bros.", subtitle: "Légendes hollywoodiennes", category: .studio, querySource: .company(174), type: .movie, accentColorHex: "#004B93", systemSymbol: "shield.fill", logoPath: "/zhD3hhtKB5qyv7ZeL4uLpNxgMVU.png"),
        BrandHub(id: "disney-studio", name: "Walt Disney", subtitle: "Classiques & animation culte", category: .studio, querySource: .company(2), type: .movie, accentColorHex: "#1B56D8", systemSymbol: "wand.and.stars", logoPath: "/wdrCwmRnLFJhEoH8GSfymY85KHT.png"),
        BrandHub(id: "universal-movies", name: "Universal", subtitle: "Franchises planétaires", category: .studio, querySource: .company(33), type: .movie, accentColorHex: "#D4AF37", systemSymbol: "globe.americas.fill", logoPath: "/8lvHyhjr8oUKOOy2dKXoALWKdp0.png"),
        BrandHub(id: "ghibli-movies", name: "Studio Ghibli", subtitle: "Chefs-d'œuvre de Miyazaki", category: .studio, querySource: .company(10342), type: .movie, accentColorHex: "#34C759", systemSymbol: "leaf.fill", logoPath: "/uFuxPEZRUcBTEiYIxjHJq62Vr77.png"),
        BrandHub(id: "paramount-studio", name: "Paramount", subtitle: "Grands classiques du 7e art", category: .studio, querySource: .company(4), type: .movie, accentColorHex: "#0064FF", systemSymbol: "mountain.2.fill", logoPath: "/jay6WcMgagAklUt7i9Euwj1pzTF.png"),
        BrandHub(id: "sony-movies", name: "Sony Pictures", subtitle: "Action, thriller & Columbia", category: .studio, querySource: .company(5), type: .movie, accentColorHex: "#7B61FF", systemSymbol: "camera.aperture", logoPath: "/71BqEFAF4V3qjjMPCpLuyJFB9A.png")
    ]

    /// Plateformes de streaming pour les séries
    public static let seriesPlatforms: [BrandHub] = [
        BrandHub(id: "netflix-series", name: "Netflix", subtitle: "Séries phénomènes & internationales", category: .platform, querySource: .watchProvider(8), type: .series, accentColorHex: "#E50914", systemSymbol: "play.tv.fill", logoPath: "/rK1KljqmbvO9HQa1PBFLILWah72.png"),
        BrandHub(id: "max-series", name: "Max / HBO", subtitle: "Les séries de référence mondiales", category: .platform, querySource: .watchProvider(1899), type: .series, accentColorHex: "#002BE7", systemSymbol: "crown.fill", logoPath: "/skypuy7SXuugIQeYg0IglmzoKaS.png"),
        BrandHub(id: "appletv-series", name: "Apple TV+", subtitle: "Séries Apple Original d'exception", category: .platform, querySource: .watchProvider(350), type: .series, accentColorHex: "#FFFFFF", systemSymbol: "apple.logo", logoPath: "/9icYBfYFcwgCbky5VdGUIKJ4C5i.png"),
        BrandHub(id: "prime-series", name: "Prime Video", subtitle: "Créations & sagas exclusives", category: .platform, querySource: .watchProvider(119), type: .series, accentColorHex: "#00A8E1", systemSymbol: "play.rectangle.fill", logoPath: "/gMZdpavHmxFNnLpMHwVxfqeux2g.png"),
        BrandHub(id: "disney-series", name: "Disney+", subtitle: "Star Wars, Marvel & Star", category: .platform, querySource: .watchProvider(337), type: .series, accentColorHex: "#113CCF", systemSymbol: "sparkles.tv.fill", logoPath: "/5eZ872CghnHFLB1j8grszbrx0dx.png"),
        BrandHub(id: "canal-series", name: "Canal+ Séries", subtitle: "Créations Originales françaises", category: .platform, querySource: .watchProvider(381), type: .series, accentColorHex: "#000000", systemSymbol: "tv.fill", logoPath: "/gliWKhLJVdm7QwL1braBCRko5dx.png")
    ]

    /// Chaînes et réseaux prestigieux pour les séries
    public static let seriesNetworks: [BrandHub] = [
        BrandHub(id: "hbo-series", name: "HBO", subtitle: "La référence absolue de la télévision", category: .network, querySource: .network(49), type: .series, accentColorHex: "#9B51E0", systemSymbol: "crown.fill", logoPath: "/tuomPhY2UtuPTqqFnKMVHvSb724.png"),
        BrandHub(id: "fx-series", name: "FX", subtitle: "Récits audacieux, incisifs & primés", category: .network, querySource: .network(88), type: .series, accentColorHex: "#F2994A", systemSymbol: "flame.fill", logoPath: "/aexGjtcs42DgRtZh7zOxayiry4J.png"),
        BrandHub(id: "bbc-series", name: "BBC", subtitle: "L'excellence britannique & drames", category: .network, querySource: .network(4), type: .series, accentColorHex: "#E02020", systemSymbol: "character.book.closed.fill", logoPath: "/uJjcCg3O4DMEjM0xtno9OWFciRP.png"),
        BrandHub(id: "apple-studios-series", name: "Apple Studios", subtitle: "Science-fiction & drames majeurs", category: .network, querySource: .network(2552), type: .series, accentColorHex: "#FFFFFF", systemSymbol: "apple.logo", logoPath: "/9icYBfYFcwgCbky5VdGUIKJ4C5i.png"),
        BrandHub(id: "amc-series", name: "AMC", subtitle: "Sagas cultes & univers intenses", category: .network, querySource: .network(1743), type: .series, accentColorHex: "#EB5757", systemSymbol: "tv.and.mediabox.fill", logoPath: "/oe1xnRABeZpnI0tA50x0gB014oX.png"),
        BrandHub(id: "showtime-series", name: "Showtime", subtitle: "Thrillers psychologiques & portraits", category: .network, querySource: .network(67), type: .series, accentColorHex: "#D80027", systemSymbol: "film.stack.fill", logoPath: "/257LvQnSLHJAWf6rtJjJbxRkJhL.png")
    ]
}

/// Modèle pour une saga / collection cinématographique (ex: Star Wars, Harry Potter, Dune).
public struct SagaCollection: Identifiable, Hashable, Sendable {
    public let id: String
    public let tmdbCollectionID: Int
    public let name: String
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let partsCount: Int
    public let parts: [MediaItem]

    public init(
        id: String,
        tmdbCollectionID: Int,
        name: String,
        overview: String?,
        posterPath: String?,
        backdropPath: String?,
        partsCount: Int,
        parts: [MediaItem] = []
    ) {
        self.id = id
        self.tmdbCollectionID = tmdbCollectionID
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.partsCount = partsCount
        self.parts = parts
    }

    public var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }

    public var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    /// Liste des identifiants des grandes sagas culte à découvrir
    public static let curatedCollectionIDs: [Int] = [
        10,     // Star Wars
        1241,   // Harry Potter
        726871, // Dune
        119,    // Le Seigneur des Anneaux
        263,    // The Dark Knight
        645,    // James Bond 007
        87359,  // Mission : Impossible
        9485    // Fast & Furious
    ]
}

/// Modèle pour un festival ou cérémonie de remise de prix (Palmarès).
public struct AwardCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let badge: String
    public let subtitle: String
    public let systemSymbol: String
    public let accentColorHex: String
    public let type: MediaType
    public let tmdbIDs: [Int]

    public init(
        id: String,
        name: String,
        badge: String,
        subtitle: String,
        systemSymbol: String,
        accentColorHex: String = "#D4AF37",
        type: MediaType,
        tmdbIDs: [Int]
    ) {
        self.id = id
        self.name = name
        self.badge = badge
        self.subtitle = subtitle
        self.systemSymbol = systemSymbol
        self.accentColorHex = accentColorHex
        self.type = type
        self.tmdbIDs = tmdbIDs
    }

    /// Palmarès Films : Cannes, Oscars, Golden Globes, César
    public static let movieAwards: [AwardCategory] = [
        AwardCategory(
            id: "cannes",
            name: "Festival de Cannes",
            badge: "Palme d'Or & Sélections",
            subtitle: "Sélections officielles & chefs-d'œuvre récompensés sur la Croisette",
            systemSymbol: "crown.fill",
            accentColorHex: "#D4AF37",
            type: .movie,
            tmdbIDs: [1064213, 915935, 497828, 725201, 496243, 505177, 324544, 93755, 86837, 8967]
        ),
        AwardCategory(
            id: "oscars",
            name: "Palmarès des Oscars",
            badge: "Meilleur Film",
            subtitle: "Les grands chefs-d'œuvre récompensés par l'Academy Awards",
            systemSymbol: "trophy.fill",
            accentColorHex: "#FFD700",
            type: .movie,
            tmdbIDs: [872585, 545611, 776503, 581734, 490132, 399055, 376867, 314365, 194662, 76203]
        ),
        AwardCategory(
            id: "golden-globes",
            name: "Golden Globes",
            badge: "Cinéma & Drame",
            subtitle: "Le triomphe des films majeurs couronnés par la presse internationale",
            systemSymbol: "globe.americas.fill",
            accentColorHex: "#F5B041",
            type: .movie,
            tmdbIDs: [701387, 974950, 872585, 792307, 466420, 915935]
        ),
        AwardCategory(
            id: "cesar",
            name: "Prix & César du Cinéma",
            badge: "César du Meilleur Film",
            subtitle: "Le sommet du cinéma français et des créations francophones",
            systemSymbol: "medal.fill",
            accentColorHex: "#C5A059",
            type: .movie,
            tmdbIDs: [915935, 963745, 605886, 615643, 584962, 437557, 449176, 298312]
        )
    ]

    /// Palmarès Séries : Emmy Awards, Golden Globes & Séries Mania
    public static let seriesAwards: [AwardCategory] = [
        AwardCategory(
            id: "emmys",
            name: "Emmy Awards",
            badge: "Meilleure Série",
            subtitle: "Les séries dramatiques et comédies les plus acclamées par la critique",
            systemSymbol: "sparkles",
            accentColorHex: "#E5C158",
            type: .series,
            tmdbIDs: [76479, 119051, 95396, 110492, 210515, 97546, 87108, 67070, 1396, 1399, 100088]
        ),
        AwardCategory(
            id: "golden-globes",
            name: "Golden Globes",
            badge: "Séries & Télévision",
            subtitle: "Les fictions incontournables et acteurs plébiscités de l'année",
            systemSymbol: "globe.americas.fill",
            accentColorHex: "#F5B041",
            type: .series,
            tmdbIDs: [126308, 97546, 108545, 204541, 76331, 1396]
        ),
        AwardCategory(
            id: "series-mania",
            name: "Séries Mania",
            badge: "Grand Prix",
            subtitle: "Pépites contemporaines et récits d'auteur majeurs du petit écran",
            systemSymbol: "globe.europe.africa.fill",
            accentColorHex: "#E5A93C",
            type: .series,
            tmdbIDs: [126308, 111831, 101243, 93405, 60574, 94605]
        )
    ]
}
