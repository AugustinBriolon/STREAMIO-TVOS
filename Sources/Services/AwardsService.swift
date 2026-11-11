import Foundation

/// Service gérant l'historique complet des grandes cérémonies et festivals du cinéma & télévision.
public final class AwardsService {
    public static let shared = AwardsService()

    private var payload: AwardsPayload?
    private var distinctionsByIMDb: [String: [AwardDistinction]] = [:]
    private var distinctionsByTMDB: [Int: [AwardDistinction]] = [:]
    private var distinctionsByTitle: [String: [AwardDistinction]] = [:]
    private let queue = DispatchQueue(label: "com.vortxtv.awards-service", qos: .userInitiated)

    public init() {
        loadData()
    }

    private func loadData() {
        // Recherche dans le Bundle principal ou Bundle.module
        var fileURL: URL? = Bundle.main.url(forResource: "AwardsData", withExtension: "json")
        if fileURL == nil {
            fileURL = Bundle.main.url(forResource: "AwardsData", withExtension: "json", subdirectory: "Resources")
        }
        // Fallback chemin direct pour les tests ou Xcode previews
        if fileURL == nil {
            let possiblePath = "Sources/Resources/AwardsData.json"
            if FileManager.default.fileExists(atPath: possiblePath) {
                fileURL = URL(fileURLWithPath: possiblePath)
            }
        }

        guard let url = fileURL, let data = try? Data(contentsOf: url) else {
            print("⚠️ [AwardsService] Impossible de charger AwardsData.json")
            return
        }

        do {
            let decoded = try JSONDecoder().decode(AwardsPayload.self, from: data)
            self.payload = decoded
            buildLookupIndex(from: decoded)
            print("✨ [AwardsService] Données des cérémonies chargées avec succès (\(decoded.ceremonies.count) cérémonies)")
        } catch {
            print("❌ [AwardsService] Erreur lors du décodage de AwardsData.json: \(error)")
        }
    }

    private func buildLookupIndex(from payload: AwardsPayload) {
        let ceremonyMap = Dictionary(uniqueKeysWithValues: payload.ceremonies.map { ($0.id, $0) })
        var byIMDb: [String: [AwardDistinction]] = [:]
        var byTMDB: [Int: [AwardDistinction]] = [:]
        var byTitle: [String: [AwardDistinction]] = [:]

        for (ceremonyId, editions) in payload.editions {
            guard let info = ceremonyMap[ceremonyId] else { continue }
            for (yearStr, categories) in editions {
                guard let year = Int(yearStr) else { continue }
                for (categoryName, nominees) in categories {
                    for nominee in nominees {
                        if nominee.title.lowercased().hasPrefix("sélection") { continue }
                        let distinction = AwardDistinction(
                            ceremonyId: ceremonyId,
                            ceremonyName: info.name,
                            ceremonyBadge: info.badge,
                            accentColorHex: info.accentColorHex,
                            year: year,
                            category: categoryName,
                            won: nominee.won,
                            nominee: nominee.nominee
                        )
                        if let imdb = nominee.imdbId, imdb.hasPrefix("tt") {
                            byIMDb[imdb, default: []].append(distinction)
                        }
                        if let tmdb = nominee.tmdbId, tmdb > 0 {
                            byTMDB[tmdb, default: []].append(distinction)
                        }
                        let norm = Self.normalizeTitle(nominee.title)
                        if !norm.isEmpty {
                            byTitle[norm, default: []].append(distinction)
                        }
                    }
                }
            }
        }

        self.distinctionsByIMDb = byIMDb
        self.distinctionsByTMDB = byTMDB
        self.distinctionsByTitle = byTitle
    }

    private static func normalizeTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s*\(Saison\s*\d+\)"#, with: "", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Liste de toutes les cérémonies disponibles.
    public var ceremonies: [AwardCeremonyInfo] {
        payload?.ceremonies ?? []
    }

    /// Cérémonies applicables aux films.
    public var movieCeremonies: [AwardCeremonyInfo] {
        ceremonies.filter { $0.mediaType == "movie" || $0.mediaType == "all" }
    }

    /// Cérémonies applicables aux séries.
    public var seriesCeremonies: [AwardCeremonyInfo] {
        ceremonies.filter { $0.mediaType == "series" || $0.mediaType == "all" }
    }

    /// Obtient les informations d'une cérémonie par son identifiant.
    public func ceremony(id: String) -> AwardCeremonyInfo? {
        ceremonies.first { $0.id == id }
    }

    /// Années disponibles pour une cérémonie donnée.
    public func availableYears(for ceremonyId: String) -> [Int] {
        guard let p = payload else { return [] }
        if let direct = p.editions[ceremonyId] {
            return direct.keys.compactMap { Int($0) }.sorted(by: >)
        }
        return ceremony(id: ceremonyId)?.availableYears ?? []
    }

    /// Liste des catégories et nominés pour une cérémonie et une année spécifiques.
    public func categories(for ceremonyId: String, year: Int) -> [AwardCategoryGroup] {
        guard let p = payload,
              let ceremonyEditions = p.editions[ceremonyId],
              let yearData = ceremonyEditions[String(year)] else {
            return []
        }

        var groups: [AwardCategoryGroup] = []
        for (categoryName, nominees) in yearData {
            // Trier de sorte que les gagnants apparaissent en premier
            let sortedNominees = nominees.sorted { $0.won && !$1.won }
            groups.append(AwardCategoryGroup(category: categoryName, nominees: sortedNominees))
        }

        // Tri naturel des catégories (Meilleur Film / Meilleure Série d'abord)
        return groups.sorted { lhs, rhs in
            let l = lhs.category.lowercased()
            let r = rhs.category.lowercased()
            if l.contains("film") || l.contains("série") || l.contains("palme") {
                return true
            }
            if r.contains("film") || r.contains("série") || r.contains("palme") {
                return false
            }
            return l < r
        }
    }

    /// Liste chronologique de tous les lauréats historiques pour une catégorie donnée (ex: Meilleur Film, Palme d'Or)
    public func historicalWinners(for ceremonyId: String, matching category: String) -> [(year: Int, nominee: AwardNomineeItem)] {
        guard let p = payload, let ceremonyEditions = p.editions[ceremonyId] else { return [] }
        var results: [(year: Int, nominee: AwardNomineeItem)] = []
        let sortedYears = ceremonyEditions.keys.compactMap { Int($0) }.sorted(by: >)
        for year in sortedYears {
            guard let yearCategories = ceremonyEditions[String(year)] else { continue }
            for (catName, nominees) in yearCategories {
                let matches: Bool
                if category.lowercased().contains("toutes") || category.isEmpty {
                    matches = true
                } else if catName.localizedCaseInsensitiveContains(category) || category.localizedCaseInsensitiveContains(catName) {
                    matches = true
                } else {
                    matches = false
                }

                if matches {
                    if let winner = nominees.first(where: { $0.won }) {
                        results.append((year: year, nominee: winner))
                        break
                    }
                }
            }
        }
        return results
    }

    /// Retourne toutes les distinctions (lauréat et nominations) associées à un film ou une série.
    public func distinctions(for item: MediaItem, alternateIDs: [String] = []) -> [AwardDistinction] {
        var collected: [AwardDistinction] = []
        let candidateIDs = [item.id] + alternateIDs

        for rawID in candidateIDs {
            if rawID.hasPrefix("tt"), let hits = distinctionsByIMDb[rawID] {
                collected.append(contentsOf: hits)
            } else if rawID.hasPrefix("tmdb:"), let tmdb = Int(rawID.dropFirst(5)), let hits = distinctionsByTMDB[tmdb] {
                collected.append(contentsOf: hits)
            }
        }

        if collected.isEmpty {
            let norm = Self.normalizeTitle(item.name)
            if let hits = distinctionsByTitle[norm] {
                collected.append(contentsOf: hits)
            }
        }

        // Déduplication par identifiant unique de distinction
        var seen = Set<String>()
        let unique = collected.filter { seen.insert($0.id).inserted }

        return unique.sorted { lhs, rhs in
            if lhs.won != rhs.won { return lhs.won }
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            let lhsRank = Self.categoryPrestigeRank(lhs.category)
            let rhsRank = Self.categoryPrestigeRank(rhs.category)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.ceremonyId < rhs.ceremonyId
        }
    }

    /// Liste dédupliquée des œuvres primées (lauréates) prêtes à être affichées dans "Films primés" / "Séries primées".
    public func awardedShowcase(for type: MediaType, limit: Int = 25) -> [AwardedMediaEntry] {
        guard let p = payload else { return [] }
        let ceremonyMap = Dictionary(uniqueKeysWithValues: p.ceremonies.map { ($0.id, $0) })

        struct Candidate {
            let canonicalKey: String
            let nominee: AwardNomineeItem
            let distinction: AwardDistinction
            let prestigeRank: Int
        }

        var grouped: [String: [Candidate]] = [:]

        for (ceremonyId, editions) in p.editions {
            guard let info = ceremonyMap[ceremonyId] else { continue }
            for (yearStr, categories) in editions {
                guard let year = Int(yearStr) else { continue }
                for (categoryName, nominees) in categories {
                    for nominee in nominees {
                        guard nominee.won,
                              nominee.resolvedMediaType == type,
                              nominee.posterPath != nil,
                              !nominee.title.lowercased().hasPrefix("sélection") else { continue }

                        let validIMDb = nominee.imdbId.flatMap { $0.hasPrefix("tt") ? $0 : nil }
                        let validTMDB = nominee.tmdbId.flatMap { $0 > 0 ? $0 : nil }
                        guard validIMDb != nil || validTMDB != nil else { continue }

                        let key = validIMDb ?? "tmdb:\(validTMDB!)"
                        let distinction = AwardDistinction(
                            ceremonyId: ceremonyId,
                            ceremonyName: info.name,
                            ceremonyBadge: info.badge,
                            accentColorHex: info.accentColorHex,
                            year: year,
                            category: categoryName,
                            won: true,
                            nominee: nominee.nominee
                        )
                        grouped[key, default: []].append(
                            Candidate(
                                canonicalKey: key,
                                nominee: nominee,
                                distinction: distinction,
                                prestigeRank: Self.categoryPrestigeRank(categoryName)
                            )
                        )
                    }
                }
            }
        }

        var entries: [AwardedMediaEntry] = []
        entries.reserveCapacity(grouped.count)

        for (_, candidates) in grouped {
            guard let best = candidates.min(by: { lhs, rhs in
                if lhs.prestigeRank != rhs.prestigeRank { return lhs.prestigeRank < rhs.prestigeRank }
                return lhs.distinction.year > rhs.distinction.year
            }) else { continue }

            let mediaItem = best.nominee.toMediaItem(category: best.distinction.category, year: best.distinction.year)
            let allDistinctions = distinctions(for: mediaItem)
            let totalWins = max(candidates.count, allDistinctions.filter(\.won).count)
            let totalNoms = max(totalWins, allDistinctions.count)

            entries.append(
                AwardedMediaEntry(
                    item: mediaItem,
                    primaryDistinction: best.distinction,
                    totalWins: totalWins,
                    totalNominations: totalNoms
                )
            )
        }

        return Array(
            entries.sorted { lhs, rhs in
                let lRecent = lhs.primaryDistinction.year
                let rRecent = rhs.primaryDistinction.year
                if lRecent != rRecent { return lRecent > rRecent }
                let lPrestige = Self.categoryPrestigeRank(lhs.primaryDistinction.category)
                let rPrestige = Self.categoryPrestigeRank(rhs.primaryDistinction.category)
                if lPrestige != rPrestige { return lPrestige < rPrestige }
                if lhs.totalWins != rhs.totalWins { return lhs.totalWins > rhs.totalWins }
                return lhs.item.name < rhs.item.name
            }
            .prefix(limit)
        )
    }

    private static func categoryPrestigeRank(_ category: String) -> Int {
        let c = category.lowercased()
        if c.contains("palme") || c.contains("meilleur film") || c.contains("best picture") || c.contains("best motion picture") || c.contains("meilleure série") || c.contains("drama series") || c.contains("comedy series") || c.contains("grand prix") {
            return 0
        }
        if c.contains("réalisat") || c.contains("director") || c.contains("scénario") || c.contains("screenplay") {
            return 1
        }
        if c.contains("acteur") || c.contains("actrice") || c.contains("actor") || c.contains("actress") || c.contains("rôle") || c.contains("interprétation") {
            return 2
        }
        if c.contains("animation") || c.contains("international") || c.contains("étranger") || c.contains("foreign") {
            return 3
        }
        return 4
    }
}
