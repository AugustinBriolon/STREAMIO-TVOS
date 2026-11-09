import Foundation
import Observation

@MainActor
@Observable
final class DetailViewModel {
    let item: MediaItem
    private(set) var detail: MediaDetail?
    private(set) var state: LoadState = .idle
    private(set) var similar: [MediaItem] = []
    var selectedSeason: Int?

    @ObservationIgnored private let service: StremioProviding
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(item: MediaItem, service: StremioProviding = StremioService()) {
        self.item = item
        self.service = service
    }

    /// Detail summary once loaded, catalog item before.
    var summary: MediaItem { detail?.summary ?? item }
    var episodes: [VideoItem] { detail?.videos ?? [] }

    /// Regular seasons ascending, specials (0) last.
    var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted { ($0 == 0 ? Int.max : $0) < ($1 == 0 ? Int.max : $1) }
    }

    var episodesInSelectedSeason: [VideoItem] {
        episodes.filter { $0.season == selectedSeason }.sorted { $0.episodeNumber < $1.episodeNumber }
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
            detail = try await service.fetchDetails(type: item.type, id: item.id)
            selectedSeason = resumeSeason.flatMap { seasons.contains($0) ? $0 : nil } ?? seasons.first
            state = .loaded
        } catch {
            state = .failure(error)
            return
        }
        await loadSimilar()
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
