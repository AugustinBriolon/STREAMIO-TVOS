import Foundation
import Observation

/// One playback: a title (and episode), the ordered streams to try, and where to resume.
struct PlaybackSession: Identifiable, Equatable {
    let id = UUID()
    let item: MediaItem
    let video: VideoItem?
    let episodes: [VideoItem]
    let candidates: [StreamItem]
    let resumePosition: Double?

    var videoID: String { video?.id ?? item.id }
    var nextEpisode: VideoItem? { video.flatMap { episodes.episode(after: $0) } }
    var subtitle: String? { video.map { "\($0.code) · \($0.cleanName ?? "Épisode \($0.episodeNumber)")" } }
}

/// Resolves "Lecture" into a playable session (best stream, resume point, next episode) and records progress.
@MainActor
@Observable
final class PlaybackCoordinator {
    private(set) var session: PlaybackSession?
    /// The title whose streams are being looked up, between the click on "Lecture" and the player opening.
    private(set) var resolvingItem: MediaItem?
    var isResolving: Bool { resolvingItem != nil }
    var errorMessage: String?

    @ObservationIgnored private let service: StremioProviding
    @ObservationIgnored private let addons: AddonStore
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let device: DeviceCapabilities

    init(service: StremioProviding, addons: AddonStore, library: LibraryStore, device: DeviceCapabilities? = nil) {
        self.service = service
        self.addons = addons
        self.library = library
        self.device = device ?? .current
    }

    /// Plays `video` (or, for a series without one, the resume/first episode). `preferred` comes from the source picker.
    func play(item: MediaItem, video: VideoItem? = nil, episodes: [VideoItem]? = nil, preferred: StreamItem? = nil) async {
        guard !isResolving else { return }
        guard !addons.urls.isEmpty else {
            return fail("Aucun addon n'est configuré. Ajoutez-en un dans Réglages.")
        }
        // Drop any prior session first so a new PlayerView cannot overlap a live VLC instance.
        if session != nil { close() }
        resolvingItem = item
        defer { resolvingItem = nil }

        var allEpisodes = episodes ?? []
        if item.type == .series, episodes == nil {
            allEpisodes = (try? await service.fetchDetails(type: .series, id: item.id).videos) ?? []
        }
        let target = video ?? (item.type == .series
            ? library.resumeEntry(forTitle: item.id)?.video ?? allEpisodes.firstEpisode
            : nil)
        if item.type == .series, target == nil {
            return fail("Aucun épisode disponible pour cette série.")
        }

        let videoID = target?.id ?? item.id
        var candidates: [StreamItem]
        if let preferred {
            candidates = [preferred]
        } else {
            let streams = await service.fetchStreams(type: item.type, id: videoID, addonBaseURLs: addons.urls)
            candidates = StreamRanker.playbackCandidates(streams, device: device)
        }
        guard !candidates.isEmpty else {
            return fail("Aucune source lisible sur Apple TV. Essayez « Choisir une source » ou un addon Debrid.")
        }

        session = PlaybackSession(
            item: item, video: target, episodes: allEpisodes,
            candidates: candidates, resumePosition: library.resumePosition(for: videoID)
        )
    }

    func playNextEpisode() async {
        guard let current = session, let next = current.nextEpisode else { return }
        await play(item: current.item, video: next, episodes: current.episodes)
    }

    /// Saves progress; once an episode is finished the next one is queued in "Reprendre la lecture".
    func recordProgress(position: Double, duration: Double) {
        guard let session else { return }
        library.updateProgress(item: session.item, video: session.video, position: position, duration: duration)
        if library.isWatched(session.videoID), let next = session.nextEpisode {
            library.queueNextEpisode(item: session.item, next: next)
        }
    }

    /// Every candidate failed to open.
    func playbackFailed() {
        fail("Le flux n'a pas pu être lu (format non supporté par Apple TV ou lien expiré). Essayez une autre source.")
    }

    func close() {
        session = nil
    }

    private func fail(_ message: String) {
        session = nil
        errorMessage = message
    }
}

