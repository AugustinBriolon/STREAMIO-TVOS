import Foundation

public enum StremioError: LocalizedError, Equatable {
    case invalidURL
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Adresse invalide."
        case .badStatus(let code): return "Le serveur a répondu avec l'erreur \(code)."
        }
    }
}

/// Network boundary for Cinemeta and stream addons; stubbed in tests.
public protocol StremioProviding: Sendable {
    func fetchCatalog(type: MediaType, genre: String?) async throws -> [MediaItem]
    func searchCatalog(type: MediaType, query: String) async throws -> [MediaItem]
    func fetchDetails(type: MediaType, id: String) async throws -> MediaDetail
    func fetchDetails(type: MediaType, id: String, language: String, tmdbApiKey: String?) async throws -> MediaDetail
    /// Queries every addon in parallel; a failing addon is skipped, not fatal.
    func fetchStreams(type: MediaType, id: String, addonBaseURLs: [String]) async -> [StreamItem]
    /// Récupère la fiche détaillée d'un acteur / réalisateur avec sa filmographie.
    func fetchPerson(personID: Int, language: String) async -> PersonDetail?

    // MARK: - Découverte & Catégories enrichies
    func fetchNowPlaying(language: String, region: String) async -> [MediaItem]
    func fetchTrending(type: MediaType, period: String, language: String) async -> [MediaItem]
    func fetchByWatchProvider(type: MediaType, providerID: Int, language: String, region: String) async -> [MediaItem]
    func fetchByCompany(companyID: Int, language: String) async -> [MediaItem]
    func fetchByNetwork(networkID: Int, language: String) async -> [MediaItem]
    func fetchCollection(collectionID: Int, language: String) async -> SagaCollection?
    func fetchCuratedTitles(tmdbIDs: [Int], type: MediaType, language: String) async -> [MediaItem]
}

public extension StremioProviding {
    func fetchDetails(type: MediaType, id: String, language: String, tmdbApiKey: String?) async throws -> MediaDetail {
        try await fetchDetails(type: type, id: id)
    }

    func fetchPerson(personID: Int, language: String) async -> PersonDetail? {
        nil
    }

    func fetchNowPlaying(language: String, region: String) async -> [MediaItem] { [] }
    func fetchTrending(type: MediaType, period: String, language: String) async -> [MediaItem] { [] }
    func fetchByWatchProvider(type: MediaType, providerID: Int, language: String, region: String) async -> [MediaItem] { [] }
    func fetchByCompany(companyID: Int, language: String) async -> [MediaItem] { [] }
    func fetchByNetwork(networkID: Int, language: String) async -> [MediaItem] { [] }
    func fetchCollection(collectionID: Int, language: String) async -> SagaCollection? { nil }
    func fetchCuratedTitles(tmdbIDs: [Int], type: MediaType, language: String) async -> [MediaItem] { [] }
}

public struct StremioService: StremioProviding {
    private let cinemetaBase = "https://v3-cinemeta.strem.io"
    private let session: URLSession
    private let tmdbService: TMDBService

    public init(session: URLSession = .shared) {
        self.session = session
        self.tmdbService = TMDBService(session: session)
    }

    public func fetchCatalog(type: MediaType, genre: String?) async throws -> [MediaItem] {
        let extra = genre.map { "/genre=\(Self.encodePathComponent($0))" } ?? ""
        let response: CatalogResponse = try await get("\(cinemetaBase)/catalog/\(type.rawValue)/top\(extra).json")
        return response.metas
    }

    public func searchCatalog(type: MediaType, query: String) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: CatalogResponse = try await get(
            "\(cinemetaBase)/catalog/\(type.rawValue)/top/search=\(Self.encodePathComponent(trimmed)).json"
        )
        return response.metas
    }

    public func fetchDetails(type: MediaType, id: String) async throws -> MediaDetail {
        try await fetchDetails(type: type, id: id, language: "fr", tmdbApiKey: nil)
    }

    public func fetchDetails(type: MediaType, id: String, language: String, tmdbApiKey: String?) async throws -> MediaDetail {
        let apiKey = (tmdbApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? tmdbApiKey!
            : AppPreferences.tmdbApiKey

        var canonicalID = id
        if id.hasPrefix("tmdb:") {
            let tmdbRaw = String(id.dropFirst(5))
            if let tmdbInt = Int(tmdbRaw),
               let resolved = await tmdbService.fetchExternalIMDbID(tmdbID: tmdbInt, type: type, apiKey: apiKey) {
                canonicalID = resolved
            }
        }

        let cinemeta: MediaDetail
        do {
            let response: MetaDetailResponse = try await get("\(cinemetaBase)/meta/\(type.rawValue)/\(canonicalID).json")
            cinemeta = response.meta
        } catch {
            // Cinemeta n'a pas indexé le titre : tentative de secours direct via TMDB
            if let directTMDB = await fetchDirectTMDBDetail(id: id, canonicalID: canonicalID, type: type, language: language, apiKey: apiKey) {
                return directTMDB
            }
            throw error
        }

        // Enrichissement via TMDB pour la langue et le casting complet
        if let enriched = await tmdbService.fetchEnrichedMeta(imdbID: canonicalID, type: type, language: language, apiKey: apiKey) {
            var updatedVideos = cinemeta.videos
            // Si c'est une série, traduire les épisodes de la saison 1 ou des saisons disponibles
            if type == .series, let videos = cinemeta.videos, !videos.isEmpty {
                let seasons = Array(Set(videos.map(\.season))).filter { $0 > 0 }
                // Traduire les épisodes de la première saison pour réactivité immédiate
                if let firstSeason = seasons.sorted().first {
                    let epMap = await tmdbService.fetchSeasonEpisodes(tmdbID: enriched.tmdbID, season: firstSeason, language: language, apiKey: apiKey)
                    if !epMap.isEmpty {
                        updatedVideos = videos.map { video in
                            guard video.season == firstSeason, let epInfo = epMap[video.episodeNumber] else { return video }
                            return VideoItem(
                                id: video.id,
                                name: epInfo.name ?? video.name,
                                season: video.season,
                                number: video.number,
                                episode: video.episode,
                                overview: epInfo.overview ?? video.overview,
                                thumbnail: video.thumbnail,
                                released: video.released
                            )
                        }
                    }
                }
            }

            let castNames: [String]? = enriched.castMembers.isEmpty ? cinemeta.cast : enriched.castMembers.map { $0.name }

            return MediaDetail(
                id: cinemeta.id,
                name: enriched.localizedTitle ?? cinemeta.name,
                type: cinemeta.type,
                poster: cinemeta.poster,
                background: cinemeta.background,
                logo: cinemeta.logo,
                description: enriched.localizedOverview ?? cinemeta.description,
                releaseInfo: cinemeta.releaseInfo,
                runtime: cinemeta.runtime,
                imdbRating: cinemeta.imdbRating,
                genres: enriched.localizedGenres ?? cinemeta.genres,
                cast: castNames,
                director: enriched.directors ?? cinemeta.director,
                videos: updatedVideos,
                castMembers: enriched.castMembers.isEmpty ? Self.fallbackCastMembers(from: cinemeta.cast) : enriched.castMembers
            )
        }

        // Fallback sans TMDB : créer des CastMember simples à partir de cinemeta.cast
        return MediaDetail(
            id: cinemeta.id,
            name: cinemeta.name,
            type: cinemeta.type,
            poster: cinemeta.poster,
            background: cinemeta.background,
            logo: cinemeta.logo,
            description: cinemeta.description,
            releaseInfo: cinemeta.releaseInfo,
            runtime: cinemeta.runtime,
            imdbRating: cinemeta.imdbRating,
            genres: cinemeta.genres,
            cast: cinemeta.cast,
            director: cinemeta.director,
            videos: cinemeta.videos,
            castMembers: Self.fallbackCastMembers(from: cinemeta.cast)
        )
    }

    private static func fallbackCastMembers(from cast: [String]?) -> [CastMember]? {
        guard let cast, !cast.isEmpty else { return nil }
        return cast.enumerated().map { index, name in
            CastMember(id: "cast-\(index)", name: name, character: nil, photo: nil)
        }
    }

    /// Récupère directement les métadonnées d'une œuvre auprès de TMDB lorsque Cinemeta échoue ou n'indexe pas le titre.
    private func fetchDirectTMDBDetail(id: String, canonicalID: String, type: MediaType, language: String, apiKey: String) async -> MediaDetail? {
        guard !apiKey.isEmpty else { return nil }
        var tmdbInt: Int?

        if id.hasPrefix("tmdb:") {
            tmdbInt = Int(id.dropFirst(5))
        } else if canonicalID.hasPrefix("tt") {
            let lang = TMDBService.tmdbLanguageCode(language)
            let endpoint = "https://api.themoviedb.org/3/find/\(canonicalID)?api_key=\(apiKey)&external_source=imdb_id&language=\(lang)"
            if let url = URL(string: endpoint),
               let (data, resp) = try? await session.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let find = try? JSONDecoder().decode(TMDBFindResponse.self, from: data) {
                if type == .series {
                    tmdbInt = find.tv_results?.first?.id
                } else {
                    tmdbInt = find.movie_results?.first?.id
                }
            }
        }

        guard let tmdbID = tmdbInt, tmdbID > 0 else { return nil }
        let lang = TMDBService.tmdbLanguageCode(language)

        if type == .series {
            let urlStr = "https://api.themoviedb.org/3/tv/\(tmdbID)?api_key=\(apiKey)&language=\(lang)&append_to_response=credits"
            guard let url = URL(string: urlStr),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let title = json["name"] as? String ?? json["original_name"] as? String ?? "Série"
            let overview = json["overview"] as? String
            let poster = (json["poster_path"] as? String).flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
            let backdrop = (json["backdrop_path"] as? String).flatMap { "https://image.tmdb.org/t/p/original\($0)" }
            let vote = json["vote_average"] as? Double
            let rating = vote != nil ? String(format: "%.1f", vote!) : nil
            let firstAir = json["first_air_date"] as? String
            let year = firstAir?.prefix(4).description
            let genresArr = (json["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            let credits = json["credits"] as? [String: Any]
            let castArr = (credits?["cast"] as? [[String: Any]])?.compactMap { $0["name"] as? String }

            return MediaDetail(
                id: id,
                name: title,
                type: .series,
                poster: poster,
                background: backdrop,
                logo: nil,
                description: overview,
                releaseInfo: year,
                runtime: nil,
                imdbRating: rating,
                genres: genresArr,
                cast: castArr,
                director: nil,
                videos: [],
                castMembers: []
            )
        } else {
            let urlStr = "https://api.themoviedb.org/3/movie/\(tmdbID)?api_key=\(apiKey)&language=\(lang)&append_to_response=credits"
            guard let url = URL(string: urlStr),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let title = json["title"] as? String ?? json["original_title"] as? String ?? "Film"
            let overview = json["overview"] as? String
            let poster = (json["poster_path"] as? String).flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
            let backdrop = (json["backdrop_path"] as? String).flatMap { "https://image.tmdb.org/t/p/original\($0)" }
            let vote = json["vote_average"] as? Double
            let rating = vote != nil ? String(format: "%.1f", vote!) : nil
            let releaseDate = json["release_date"] as? String
            let year = releaseDate?.prefix(4).description
            let runtimeMin = json["runtime"] as? Int
            let runtime = runtimeMin != nil ? "\(runtimeMin!) min" : nil

            let genresArr = (json["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            let credits = json["credits"] as? [String: Any]
            let castArr = (credits?["cast"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
            let crewArr = credits?["crew"] as? [[String: Any]]
            let directors = crewArr?.filter { ($0["job"] as? String) == "Director" }.compactMap { $0["name"] as? String }

            return MediaDetail(
                id: id,
                name: title,
                type: .movie,
                poster: poster,
                background: backdrop,
                logo: nil,
                description: overview,
                releaseInfo: year,
                runtime: runtime,
                imdbRating: rating,
                genres: genresArr,
                cast: castArr,
                director: directors,
                videos: nil,
                castMembers: []
            )
        }
    }

    public func fetchStreams(type: MediaType, id: String, addonBaseURLs: [String]) async -> [StreamItem] {
        var canonicalID = id
        if id.hasPrefix("tmdb:") {
            let tmdbRaw = String(id.dropFirst(5))
            let apiKey = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
            if let tmdbInt = Int(tmdbRaw),
               let resolved = await tmdbService.fetchExternalIMDbID(tmdbID: tmdbInt, type: type, apiKey: apiKey) {
                canonicalID = resolved
            }
        }

        return await withTaskGroup(of: (Int, [StreamItem]).self) { group in
            for (index, base) in addonBaseURLs.enumerated() {
                group.addTask {
                    let response: StreamsResponse? = try? await get("\(base)/stream/\(type.rawValue)/\(canonicalID).json", timeout: 15)
                    return (index, response?.streams ?? [])
                }
            }
            var byAddon: [(Int, [StreamItem])] = []
            for await result in group { byAddon.append(result) }
            // Keep the user's addon order so it acts as a tie-breaker in ranking.
            return byAddon.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    public func fetchPerson(personID: Int, language: String) async -> PersonDetail? {
        let apiKey = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchPersonDetails(personID: personID, language: language, apiKey: apiKey)
    }

    public func fetchNowPlaying(language: String, region: String = "FR") async -> [MediaItem] {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchNowPlayingMovies(language: language, region: region, apiKey: key)
    }

    public func fetchTrending(type: MediaType, period: String = "week", language: String) async -> [MediaItem] {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchTrending(type: type, period: period, language: language, apiKey: key)
    }

    public func fetchByWatchProvider(type: MediaType, providerID: Int, language: String, region: String = "FR") async -> [MediaItem] {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchByWatchProvider(type: type, providerID: providerID, language: language, region: region, apiKey: key)
    }

    public func fetchByCompany(companyID: Int, language: String) async -> [MediaItem] {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchByCompany(companyID: companyID, language: language, apiKey: key)
    }

    public func fetchByNetwork(networkID: Int, language: String) async -> [MediaItem] {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchByNetwork(networkID: networkID, language: language, apiKey: key)
    }

    public func fetchCollection(collectionID: Int, language: String) async -> SagaCollection? {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchCollection(collectionID: collectionID, language: language, apiKey: key)
    }

    public func fetchCuratedTitles(tmdbIDs: [Int], type: MediaType, language: String) async -> [MediaItem] {
        let key = await AppPreferences.shared.effectiveTMDBKey ?? AppPreferences.tmdbApiKey
        return await tmdbService.fetchCuratedTitles(tmdbIDs: tmdbIDs, type: type, language: language, apiKey: key)
    }

    private func get<T: Decodable>(_ endpoint: String, timeout: TimeInterval = 20) async throws -> T {
        guard let url = URL(string: endpoint) else { throw StremioError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StremioError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func encodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
