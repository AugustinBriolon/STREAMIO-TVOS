import Foundation

/// Modèles de décodage JSON pour l'API TMDB v3
struct TMDBFindResponse: Decodable {
    let movie_results: [TMDBFindMovieResult]?
    let tv_results: [TMDBFindTVResult]?
}

struct TMDBFindMovieResult: Decodable {
    let id: Int
}

struct TMDBFindTVResult: Decodable {
    let id: Int
}

private struct TMDBPageResponse<T: Decodable>: Decodable {
    let page: Int?
    let total_pages: Int?
    let results: [T]
}

private struct TMDBMovieItem: Decodable {
    let id: Int
    let title: String?
    let original_title: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let vote_average: Double?

    func toMediaItem() -> MediaItem {
        let displayTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title : original_title) ?? "Film"
        let year = release_date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let poster = poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" }
        let background = backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" }
        let rating = vote_average.map { String(format: "%.1f", $0) }
        return MediaItem(
            id: "tmdb:\(id)",
            name: displayTitle,
            type: .movie,
            poster: poster,
            background: background,
            description: overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            releaseInfo: year,
            imdbRating: rating
        )
    }
}

private struct TMDBTVItem: Decodable {
    let id: Int
    let name: String?
    let original_name: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let first_air_date: String?
    let vote_average: Double?

    func toMediaItem() -> MediaItem {
        let displayTitle = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name : original_name) ?? "Série"
        let year = first_air_date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let poster = poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" }
        let background = backdrop_path.map { "https://image.tmdb.org/t/p/w1280\($0)" }
        let rating = vote_average.map { String(format: "%.1f", $0) }
        return MediaItem(
            id: "tmdb:\(id)",
            name: displayTitle,
            type: .series,
            poster: poster,
            background: background,
            description: overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            releaseInfo: year,
            imdbRating: rating
        )
    }
}

private struct TMDBCollectionResponse: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let parts: [TMDBMovieItem]?
}

private struct TMDBMovieDetail: Decodable {
    let id: Int
    let title: String?
    let overview: String?
    let genres: [TMDBGenre]?
    let credits: TMDBCredits?
}

private struct TMDBTVDetail: Decodable {
    let id: Int
    let name: String?
    let overview: String?
    let genres: [TMDBGenre]?
    let credits: TMDBCredits?
}

private struct TMDBGenre: Decodable {
    let id: Int
    let name: String
}

private struct TMDBCredits: Decodable {
    let cast: [TMDBCastItem]?
    let crew: [TMDBCrewItem]?
}

private struct TMDBCastItem: Decodable {
    let id: Int
    let name: String
    let character: String?
    let profile_path: String?
    let order: Int?
}

private struct TMDBCrewItem: Decodable {
    let id: Int
    let name: String
    let job: String?
}

private struct TMDBSeasonDetail: Decodable {
    let season_number: Int
    let episodes: [TMDBEpisodeItem]?
}

private struct TMDBEpisodeItem: Decodable {
    let episode_number: Int
    let name: String?
    let overview: String?
    let still_path: String?
}

private struct TMDBPersonResponse: Decodable {
    let id: Int
    let name: String
    let biography: String?
    let profile_path: String?
    let birthday: String?
    let place_of_birth: String?
    let combined_credits: TMDBPersonCombinedCredits?
}

private struct TMDBPersonCombinedCredits: Decodable {
    let cast: [TMDBPersonCreditItem]?
}

private struct TMDBPersonCreditItem: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let media_type: String?
    let character: String?
    let release_date: String?
    let first_air_date: String?
    let poster_path: String?
    let backdrop_path: String?
    let vote_average: Double?
    let vote_count: Int?
    let popularity: Double?
    let overview: String?
}

private struct TMDBExternalIDsResponse: Decodable {
    let imdb_id: String?
}

private struct TMDBVideosResponse: Decodable {
    let results: [TMDBVideoItem]?
}

public struct TMDBVideoItem: Decodable, Equatable, Sendable {
    public let key: String?
    public let name: String?
    public let site: String?
    public let type: String?
    public let official: Bool?
    public let iso_639_1: String?

    public init(
        key: String?,
        name: String? = nil,
        site: String? = "YouTube",
        type: String?,
        official: Bool? = nil,
        iso_639_1: String?
    ) {
        self.key = key
        self.name = name
        self.site = site
        self.type = type
        self.official = official
        self.iso_639_1 = iso_639_1
    }
}

/// Résultat enrichi et traduit issu de TMDB
public struct TMDBEnrichedMeta: Sendable {
    public let tmdbID: Int
    public let localizedTitle: String?
    public let localizedOverview: String?
    public let localizedGenres: [String]?
    public let directors: [String]?
    public let castMembers: [CastMember]
    public let watchProviders: [WatchProvider]
}

/// Service de communication avec The Movie Database (TMDB v3) pour la localisation et le casting enrichi.
public struct TMDBService: Sendable {
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p/w276_and_h350_face"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Convertit un code de langue court (ex: "fr") en code BCP-47 attendu par TMDB ("fr-FR").
    public static func tmdbLanguageCode(_ code: String) -> String {
        switch code.lowercased() {
        case "fr": return "fr-FR"
        case "en": return "en-US"
        case "es": return "es-ES"
        case "de": return "de-DE"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "ja": return "ja-JP"
        default:
            return code.contains("-") ? code : "\(code)-\(code.uppercased())"
        }
    }

    /// Région JustWatch alignée sur la langue métadonnées (hubs catalogue = FR).
    public static func watchRegion(for language: String) -> String {
        switch String(language.prefix(2)).lowercased() {
        case "en": return "US"
        case "fr": return "FR"
        case "es": return "ES"
        case "de": return "DE"
        case "it": return "IT"
        case "pt": return "BR"
        case "ja": return "JP"
        default: return "FR"
        }
    }

    /// Récupère les métadonnées traduites et le casting complet à partir d'un identifiant IMDb (`tt...`).
    public func fetchEnrichedMeta(imdbID: String, type: MediaType, language: String, apiKey: String) async -> TMDBEnrichedMeta? {
        guard imdbID.hasPrefix("tt"), !apiKey.isEmpty else { return nil }
        let lang = Self.tmdbLanguageCode(language)

        // 1. Trouver le média sur TMDB via son identifiant IMDb
        let findEndpoint = "\(baseURL)/find/\(imdbID)?api_key=\(apiKey)&external_source=imdb_id&language=\(lang)"
        guard let findURL = URL(string: findEndpoint),
              let (findData, findResp) = try? await session.data(from: findURL),
              (findResp as? HTTPURLResponse)?.statusCode == 200,
              let findResult = try? JSONDecoder().decode(TMDBFindResponse.self, from: findData) else {
            return nil
        }

        let region = Self.watchRegion(for: language)
        switch type {
        case .movie:
            guard let movieItem = findResult.movie_results?.first else { return nil }
            return await fetchMovieDetail(tmdbID: movieItem.id, language: lang, region: region, apiKey: apiKey)
        case .series:
            guard let tvItem = findResult.tv_results?.first else { return nil }
            return await fetchTVDetail(tmdbID: tvItem.id, language: lang, region: region, apiKey: apiKey)
        }
    }

    /// Flatrate puis rent/buy, dédoublonnés, pour la région JustWatch.
    public static func pickWatchProviders(from regionPayload: [String: Any]?, limit: Int = 8) -> [WatchProvider] {
        guard let regionPayload else { return [] }
        var seen = Set<Int>()
        var result: [WatchProvider] = []
        for key in ["flatrate", "free", "ads", "rent", "buy"] {
            let rows = regionPayload[key] as? [[String: Any]] ?? []
            for row in rows {
                guard let id = row["provider_id"] as? Int,
                      let name = row["provider_name"] as? String,
                      seen.insert(id).inserted else { continue }
                result.append(WatchProvider(id: id, name: name, logoPath: row["logo_path"] as? String))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    public func fetchWatchProviders(tmdbID: Int, type: MediaType, region: String, apiKey: String) async -> [WatchProvider] {
        guard !apiKey.isEmpty else { return [] }
        let path = type == .movie ? "movie" : "tv"
        let endpoint = "\(baseURL)/\(path)/\(tmdbID)/watch/providers?api_key=\(apiKey)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = payload["results"] as? [String: Any] else {
            return []
        }
        let regionPayload = results[region] as? [String: Any]
            ?? results["FR"] as? [String: Any]
            ?? results["US"] as? [String: Any]
        return Self.pickWatchProviders(from: regionPayload)
    }

    /// Clé YouTube de la bande-annonce (Trailer > Teaser), via IMDb ou id `tmdb:`.
    /// Prefers videos in `language` (metadata preference), then English, then any.
    public func fetchYouTubeTrailerKey(id: String, type: MediaType, language: String, apiKey: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let tmdbID: Int
        if id.hasPrefix("tmdb:"), let raw = Int(id.dropFirst(5)) {
            tmdbID = raw
        } else if id.hasPrefix("tt") {
            let findEndpoint = "\(baseURL)/find/\(id)?api_key=\(apiKey)&external_source=imdb_id"
            guard let findURL = URL(string: findEndpoint),
                  let (findData, findResp) = try? await session.data(from: findURL),
                  (findResp as? HTTPURLResponse)?.statusCode == 200,
                  let findResult = try? JSONDecoder().decode(TMDBFindResponse.self, from: findData) else {
                return nil
            }
            switch type {
            case .movie:
                guard let movie = findResult.movie_results?.first else { return nil }
                tmdbID = movie.id
            case .series:
                guard let show = findResult.tv_results?.first else { return nil }
                tmdbID = show.id
            }
        } else {
            return nil
        }

        let lang = Self.tmdbLanguageCode(language)
        let short = String(lang.prefix(2)).lowercased()
        var includeLangs = [short]
        if short != "en" { includeLangs.append("en") }
        includeLangs.append("null")
        let path = type == .movie ? "movie" : "tv"
        let endpoint =
            "\(baseURL)/\(path)/\(tmdbID)/videos?api_key=\(apiKey)&language=\(lang)&include_video_language=\(includeLangs.joined(separator: ","))"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(TMDBVideosResponse.self, from: data),
              let results = payload.results else {
            return nil
        }

        let youtube = results.filter { ($0.site ?? "").caseInsensitiveCompare("YouTube") == .orderedSame }
        guard let key = Self.pickTrailerKey(from: youtube, preferredLanguage: short) else { return nil }
        return key
    }

    /// Trailer/Teaser in preferred language first, then English, then any.
    /// Prefers official uploads and demotes auto-dub / AI labels in the TMDB name.
    public static func pickTrailerKey(from videos: [TMDBVideoItem], preferredLanguage: String) -> String? {
        let preferred = preferredLanguage.lowercased()
        let ranked = videos.sorted { lhs, rhs in
            trailerRank(lhs, preferred: preferred) > trailerRank(rhs, preferred: preferred)
        }
        let key = ranked.first?.key?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }

    static func trailerRank(_ video: TMDBVideoItem, preferred: String) -> Int {
        let type = (video.type ?? "").lowercased()
        let lang = (video.iso_639_1 ?? "").lowercased()
        let name = (video.name ?? "").lowercased()
        var score = 0
        switch type {
        case "trailer": score += 300
        case "teaser": score += 200
        default: score += 50
        }
        if lang == preferred { score += 200 }
        else if lang == "en" && preferred != "en" { score += 80 }
        else if lang.isEmpty { score += 40 }
        if video.official == true { score += 40 }
        if preferred == "fr", name.contains("vf") || name.contains("français") || name.contains("french") {
            score += 30
        }
        // YouTube auto-dub uploads often land in TMDB with a localized iso code — skip when named as such.
        if name.contains("auto") && (name.contains("dub") || name.contains("doubl")) { score -= 400 }
        if name.contains("ai dub") || name.contains("machine") { score -= 400 }
        return score
    }

    /// Récupère la liste des épisodes traduits pour une saison donnée.
    public func fetchSeasonEpisodes(tmdbID: Int, season: Int, language: String, apiKey: String) async -> [Int: (name: String?, overview: String?)] {
        guard !apiKey.isEmpty else { return [:] }
        let lang = Self.tmdbLanguageCode(language)
        let endpoint = "\(baseURL)/tv/\(tmdbID)/season/\(season)?api_key=\(apiKey)&language=\(lang)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let seasonDetail = try? JSONDecoder().decode(TMDBSeasonDetail.self, from: data),
              let episodes = seasonDetail.episodes else {
            return [:]
        }

        var map: [Int: (name: String?, overview: String?)] = [:]
        for ep in episodes {
            map[ep.episode_number] = (ep.name, ep.overview)
        }
        return map
    }

    /// Récupère la fiche détaillée d'une personne avec sa filmographie (films et séries dédoublonnés et triés).
    public func fetchPersonDetails(personID: Int, language: String, apiKey: String) async -> PersonDetail? {
        guard !apiKey.isEmpty else { return nil }
        let lang = Self.tmdbLanguageCode(language)
        let endpoint = "\(baseURL)/person/\(personID)?api_key=\(apiKey)&append_to_response=combined_credits&language=\(lang)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let person = try? JSONDecoder().decode(TMDBPersonResponse.self, from: data) else {
            return nil
        }

        let rawCast = person.combined_credits?.cast ?? []
        var seenIDs = Set<Int>()
        var credits: [PersonCredit] = []

        for item in rawCast {
            guard !seenIDs.contains(item.id) else { continue }
            seenIDs.insert(item.id)

            let isTV = item.media_type == "tv"
            let type: MediaType = isTV ? .series : .movie
            let displayTitle = (isTV ? item.name : item.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title = displayTitle, !title.isEmpty else { continue }

            let releaseDate = isTV ? item.first_air_date : item.release_date
            let cleanChar = item.character?.trimmingCharacters(in: .whitespacesAndNewlines)

            credits.append(
                PersonCredit(
                    id: "tmdb:\(item.id)",
                    tmdbID: item.id,
                    title: title,
                    type: type,
                    character: cleanChar?.isEmpty == false ? cleanChar : nil,
                    releaseDate: releaseDate,
                    posterPath: item.poster_path,
                    backdropPath: item.backdrop_path,
                    voteAverage: item.vote_average,
                    popularity: item.popularity
                )
            )
        }

        credits.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }

        return PersonDetail(
            id: "\(person.id)",
            name: person.name,
            biography: person.biography?.trimmingCharacters(in: .whitespacesAndNewlines),
            profilePath: person.profile_path,
            birthday: person.birthday,
            placeOfBirth: person.place_of_birth,
            credits: credits
        )
    }

    /// Résout l'identifiant IMDb (`tt...`) à partir d'un identifiant TMDB numérique.
    public func fetchExternalIMDbID(tmdbID: Int, type: MediaType, apiKey: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let typePath = (type == .series) ? "tv" : "movie"
        let endpoint = "\(baseURL)/\(typePath)/\(tmdbID)/external_ids?api_key=\(apiKey)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(TMDBExternalIDsResponse.self, from: data) else {
            return nil
        }
        return result.imdb_id?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Découverte & Catégories

    /// Films actuellement à l'affiche au cinéma (région France par défaut)
    public func fetchNowPlayingMovies(language: String, region: String = "FR", apiKey: String) async -> [MediaItem] {
        guard !apiKey.isEmpty else { return [] }
        let lang = Self.tmdbLanguageCode(language)
        let endpoint = "\(baseURL)/movie/now_playing?api_key=\(apiKey)&language=\(lang)&region=\(region)&page=1"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let page = try? JSONDecoder().decode(TMDBPageResponse<TMDBMovieItem>.self, from: data) else {
            return []
        }
        return page.results.map { $0.toMediaItem() }
    }

    /// Tendances de la semaine ou du jour pour films ou séries
    public func fetchTrending(type: MediaType, period: String = "week", language: String, apiKey: String) async -> [MediaItem] {
        guard !apiKey.isEmpty else { return [] }
        let lang = Self.tmdbLanguageCode(language)
        let typePath = (type == .series) ? "tv" : "movie"
        let endpoint = "\(baseURL)/trending/\(typePath)/\(period)?api_key=\(apiKey)&language=\(lang)&page=1"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }

        switch type {
        case .movie:
            let page = try? JSONDecoder().decode(TMDBPageResponse<TMDBMovieItem>.self, from: data)
            return page?.results.map { $0.toMediaItem() } ?? []
        case .series:
            let page = try? JSONDecoder().decode(TMDBPageResponse<TMDBTVItem>.self, from: data)
            return page?.results.map { $0.toMediaItem() } ?? []
        }
    }

    /// One discover page for a watch provider. Hub UI appends pages as the user scrolls.
    public func fetchByWatchProvider(
        type: MediaType,
        providerID: Int,
        language: String,
        region: String = "FR",
        page: Int = 1,
        apiKey: String
    ) async -> DiscoverPage {
        guard !apiKey.isEmpty else { return DiscoverPage(items: [], page: page, totalPages: 1) }
        let lang = Self.tmdbLanguageCode(language)
        let typePath = (type == .series) ? "tv" : "movie"
        let endpoint = "\(baseURL)/discover/\(typePath)?api_key=\(apiKey)&language=\(lang)&watch_region=\(region)&with_watch_providers=\(providerID)&sort_by=popularity.desc&page=\(page)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            return DiscoverPage(items: [], page: page, totalPages: page)
        }
        switch type {
        case .movie:
            let decoded = try? JSONDecoder().decode(TMDBPageResponse<TMDBMovieItem>.self, from: data)
            return DiscoverPage(
                items: decoded?.results.map { $0.toMediaItem() } ?? [],
                page: page,
                totalPages: decoded?.total_pages ?? page
            )
        case .series:
            let decoded = try? JSONDecoder().decode(TMDBPageResponse<TMDBTVItem>.self, from: data)
            return DiscoverPage(
                items: decoded?.results.map { $0.toMediaItem() } ?? [],
                page: page,
                totalPages: decoded?.total_pages ?? page
            )
        }
    }

    /// One discover page for a production company.
    public func fetchByCompany(companyID: Int, language: String, page: Int = 1, apiKey: String) async -> DiscoverPage {
        guard !apiKey.isEmpty else { return DiscoverPage(items: [], page: page, totalPages: 1) }
        let lang = Self.tmdbLanguageCode(language)
        let endpoint = "\(baseURL)/discover/movie?api_key=\(apiKey)&language=\(lang)&with_companies=\(companyID)&sort_by=popularity.desc&page=\(page)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TMDBPageResponse<TMDBMovieItem>.self, from: data) else {
            return DiscoverPage(items: [], page: page, totalPages: page)
        }
        return DiscoverPage(
            items: decoded.results.map { $0.toMediaItem() },
            page: page,
            totalPages: decoded.total_pages ?? page
        )
    }

    /// One discover page for a TV network.
    public func fetchByNetwork(networkID: Int, language: String, page: Int = 1, apiKey: String) async -> DiscoverPage {
        guard !apiKey.isEmpty else { return DiscoverPage(items: [], page: page, totalPages: 1) }
        let lang = Self.tmdbLanguageCode(language)
        let endpoint = "\(baseURL)/discover/tv?api_key=\(apiKey)&language=\(lang)&with_networks=\(networkID)&sort_by=popularity.desc&page=\(page)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TMDBPageResponse<TMDBTVItem>.self, from: data) else {
            return DiscoverPage(items: [], page: page, totalPages: page)
        }
        return DiscoverPage(
            items: decoded.results.map { $0.toMediaItem() },
            page: page,
            totalPages: decoded.total_pages ?? page
        )
    }

    /// Détail complet d'une saga / collection avec tous ses volets ordonnés
    public func fetchCollection(collectionID: Int, language: String, apiKey: String) async -> SagaCollection? {
        guard !apiKey.isEmpty else { return nil }
        let lang = Self.tmdbLanguageCode(language)
        let endpoint = "\(baseURL)/collection/\(collectionID)?api_key=\(apiKey)&language=\(lang)"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let collection = try? JSONDecoder().decode(TMDBCollectionResponse.self, from: data) else {
            return nil
        }

        let rawParts = collection.parts ?? []
        // Announced films have no date yet: they go last, not first.
        let undated = "9999"
        let sortedParts = rawParts.sorted {
            ($0.release_date.flatMap { $0.isEmpty ? nil : $0 } ?? undated) < ($1.release_date.flatMap { $0.isEmpty ? nil : $0 } ?? undated)
        }
        let items = sortedParts.map { $0.toMediaItem() }

        return SagaCollection(
            id: "collection:\(collection.id)",
            tmdbCollectionID: collection.id,
            name: collection.name,
            overview: collection.overview,
            posterPath: collection.poster_path,
            backdropPath: collection.backdrop_path,
            partsCount: items.count,
            parts: items
        )
    }

    /// Récupère en parallèle une sélection de titres par leurs identifiants TMDB (ex: palmarès de festivals)
    public func fetchCuratedTitles(tmdbIDs: [Int], type: MediaType, language: String, apiKey: String) async -> [MediaItem] {
        guard !apiKey.isEmpty, !tmdbIDs.isEmpty else { return [] }
        let lang = Self.tmdbLanguageCode(language)
        let typePath = (type == .series) ? "tv" : "movie"

        return await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, id) in tmdbIDs.enumerated() {
                group.addTask {
                    let endpoint = "\(self.baseURL)/\(typePath)/\(id)?api_key=\(apiKey)&language=\(lang)"
                    guard let url = URL(string: endpoint),
                          let (data, resp) = try? await self.session.data(from: url),
                          (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        return (index, nil)
                    }

                    switch type {
                    case .movie:
                        let movie = try? JSONDecoder().decode(TMDBMovieItem.self, from: data)
                        return (index, movie?.toMediaItem())
                    case .series:
                        let tv = try? JSONDecoder().decode(TMDBTVItem.self, from: data)
                        return (index, tv?.toMediaItem())
                    }
                }
            }

            var results = [(Int, MediaItem)](repeating: (0, MediaItem(id: "", name: "", type: type)), count: tmdbIDs.count)
            var collected = [Int: MediaItem]()
            for await (index, item) in group {
                if let item { collected[index] = item }
            }
            return tmdbIDs.indices.compactMap { collected[$0] }
        }
    }

    // MARK: - Privé

    private func fetchMovieDetail(tmdbID: Int, language: String, region: String, apiKey: String) async -> TMDBEnrichedMeta? {
        let endpoint = "\(baseURL)/movie/\(tmdbID)?api_key=\(apiKey)&language=\(language)&append_to_response=credits"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let detail = try? JSONDecoder().decode(TMDBMovieDetail.self, from: data) else {
            return nil
        }

        let directors = detail.credits?.crew?
            .filter { $0.job?.lowercased() == "director" }
            .map(\.name)

        let castMembers = (detail.credits?.cast ?? [])
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            .prefix(25)
            .map { item in
                CastMember(
                    id: "\(item.id)",
                    name: item.name,
                    character: item.character?.isEmpty == false ? item.character : nil,
                    photo: item.profile_path.map { "\(imageBaseURL)\($0)" }
                )
            }

        let cleanTitle = detail.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOverview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providersEnabled = await MainActor.run { AppPreferences.shared.showWatchProviders }
        let providers = providersEnabled
            ? await fetchWatchProviders(tmdbID: tmdbID, type: .movie, region: region, apiKey: apiKey)
            : []

        return TMDBEnrichedMeta(
            tmdbID: tmdbID,
            localizedTitle: cleanTitle?.isEmpty == false ? cleanTitle : nil,
            localizedOverview: cleanOverview?.isEmpty == false ? cleanOverview : nil,
            localizedGenres: detail.genres?.map(\.name),
            directors: directors?.isEmpty == false ? directors : nil,
            castMembers: Array(castMembers),
            watchProviders: providers
        )
    }

    private func fetchTVDetail(tmdbID: Int, language: String, region: String, apiKey: String) async -> TMDBEnrichedMeta? {
        let endpoint = "\(baseURL)/tv/\(tmdbID)?api_key=\(apiKey)&language=\(language)&append_to_response=credits"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let detail = try? JSONDecoder().decode(TMDBTVDetail.self, from: data) else {
            return nil
        }

        let directors = detail.credits?.crew?
            .filter { ["director", "creator", "series director"].contains($0.job?.lowercased()) }
            .map(\.name)

        let castMembers = (detail.credits?.cast ?? [])
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            .prefix(25)
            .map { item in
                CastMember(
                    id: "\(item.id)",
                    name: item.name,
                    character: item.character?.isEmpty == false ? item.character : nil,
                    photo: item.profile_path.map { "\(imageBaseURL)\($0)" }
                )
            }

        let cleanTitle = detail.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOverview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providersEnabled = await MainActor.run { AppPreferences.shared.showWatchProviders }
        let providers = providersEnabled
            ? await fetchWatchProviders(tmdbID: tmdbID, type: .series, region: region, apiKey: apiKey)
            : []

        return TMDBEnrichedMeta(
            tmdbID: tmdbID,
            localizedTitle: cleanTitle?.isEmpty == false ? cleanTitle : nil,
            localizedOverview: cleanOverview?.isEmpty == false ? cleanOverview : nil,
            localizedGenres: detail.genres?.map(\.name),
            directors: directors?.isEmpty == false ? directors : nil,
            castMembers: Array(castMembers),
            watchProviders: providers
        )
    }
}
