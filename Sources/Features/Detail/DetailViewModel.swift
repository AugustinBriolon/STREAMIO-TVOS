import Foundation
import Observation

enum StreamAvailability: Equatable {
    case idle
    case checking
    case available(playableCount: Int, totalCount: Int)
    case unavailable(notices: [String], totalCount: Int)
    case noAddons

    var hasPlayableStream: Bool {
        if case .available = self { return true }
        return false
    }
}

@MainActor
@Observable
final class DetailViewModel {
    let item: MediaItem
    private(set) var detail: MediaDetail?
    private(set) var state: LoadState = .idle
    private(set) var similar: [MediaItem] = []
    private(set) var distinctions: [AwardDistinction] = []
    private(set) var availability: StreamAvailability = .idle
    private(set) var prefetchedStreams: [StreamItem] = []
    private(set) var checkedVideoID: String?
    var selectedSeason: Int?

    @ObservationIgnored private let service: StremioProviding
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var checkedSignature: String?

    init(item: MediaItem, service: StremioProviding = StremioService()) {
        self.item = item
        self.service = service
        self.distinctions = AwardsService.shared.distinctions(for: item)
    }

    /// Detail summary once loaded, catalog item before.
    var summary: MediaItem { detail?.summary ?? item }
    /// The backdrop the page opened with stays for the whole visit: the detail metadata often names a
    /// different image, and swapping it once loaded made the page jump. Only a catalog item without an
    /// image of its own takes the one from the details.
    var backdropURL: URL? { item.background != nil ? item.backgroundURL : summary.backgroundURL }
    var episodes: [VideoItem] { detail?.videos ?? [] }

    /// Tous les identifiants connus pour ce titre (pré-résolution TMDB + canonique IMDb) pour Ma liste / reprise / distinctions.
    var idAliases: [String] {
        Array(Set([item.id, summary.id]))
    }

    /// Regular seasons ascending, specials (0) last.
    var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted { ($0 == 0 ? Int.max : $0) < ($1 == 0 ? Int.max : $1) }
    }

    var episodesInSelectedSeason: [VideoItem] {
        episodes.filter { $0.season == selectedSeason }.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    var castMembers: [CastMember] {
        detail?.castMembers ?? []
    }

    var castLine: String? {
        guard let cast = detail?.cast, !cast.isEmpty else { return nil }
        return cast.prefix(4).joined(separator: ", ")
    }

    var directorLine: String? {
        guard let director = detail?.director, !director.isEmpty else { return nil }
        return director.joined(separator: ", ")
    }

    static func seasonLabel(_ season: Int) -> String {
        season == 0 ? "Spéciaux" : "Saison \(season)"
    }

    /// Loads once, in a model-owned task so a view lifecycle cancellation cannot leave the page half-loaded.
    /// `resumeSeason` opens the season of the episode the user is watching.
    func loadIfNeeded(resumeSeason: Int?) async {
        if state == .idle || state.isFailure { loadTask = Task { await load(resumeSeason: resumeSeason) } }
        await loadTask?.value
    }

    private func load(resumeSeason: Int?) async {
        state = .loading
        do {
            let prefs = AppPreferences.shared
            detail = try await service.fetchDetails(
                type: item.type,
                id: item.id,
                language: prefs.metadataLanguage,
                tmdbApiKey: prefs.effectiveTMDBKey
            )
            if let loadedSummary = detail?.summary {
                distinctions = AwardsService.shared.distinctions(
                    for: loadedSummary,
                    alternateIDs: [item.id]
                )
            }
            selectedSeason = resumeSeason.flatMap { seasons.contains($0) ? $0 : nil } ?? seasons.first
            state = .loaded
        } catch {
            state = .failure(error)
            return
        }
        await loadSimilar()
    }

    /// Returns streams already fetched during availability check when they match `videoID`.
    func prefetchedStreams(for videoID: String) -> [StreamItem]? {
        checkedVideoID == videoID ? prefetchedStreams : nil
    }

    /// Checks once per (videoID, addons) whether at least one playable stream exists on this Apple TV.
    func checkAvailability(addons: [String], targetVideoID: String?, device: DeviceCapabilities = .all) async {
        guard !addons.isEmpty else {
            prefetchedStreams = []
            checkedVideoID = nil
            availability = .noAddons
            return
        }

        let checkID: String? = switch item.type {
        case .movie: summary.id
        case .series: targetVideoID ?? episodes.firstEpisode?.id
        }
        guard let checkID else { return }

        let signature = "\(checkID)|\(addons.joined(separator: ","))"
        guard checkedSignature != signature else { return }
        checkedSignature = signature

        availability = .checking
        let fetched = await service.fetchStreams(type: item.type, id: checkID, addonBaseURLs: addons)
        let ranked = StreamRanker.rank(fetched, device: device)
        prefetchedStreams = ranked
        checkedVideoID = checkID

        let playable = ranked.filter(\.isPlayable)
        if !playable.isEmpty {
            availability = .available(playableCount: playable.count, totalCount: ranked.count)
        } else {
            var seen = Set<String>()
            let notices = ranked.filter(\.isNotice)
                .map(\.fullDescription)
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            availability = .unavailable(notices: notices, totalCount: ranked.count)
        }
    }

    /// Same first genre, excluding this title. Cinemeta has no recommendation endpoint.
    private func loadSimilar() async {
        guard let genre = summary.genres?.first else { return }
        let items = (try? await service.fetchCatalog(type: item.type, genre: genre)) ?? []
        similar = Array(items.filter { $0.id != item.id }.prefix(15))
    }
}

extension PlaybackProgress {
    /// Primary button title on the detail page: "Reprendre S1:É3", "Lecture S1:É4"…
    var resumeButtonTitle: String {
        let verb = position >= LibraryStore.minimumResumeSeconds ? "Reprendre" : "Lecture"
        return video.map { "\(verb) \($0.code)" } ?? verb
    }

    var remainingLabel: String? {
        guard position >= LibraryStore.minimumResumeSeconds, let minutes = remainingMinutes else { return nil }
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min restantes" : "\(minutes) min restantes"
    }
}
