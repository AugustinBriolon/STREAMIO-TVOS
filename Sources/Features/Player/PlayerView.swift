import AVKit
import SwiftUI

/// Full-screen AVPlayer bound to the current `PlaybackSession`.
struct PlayerView: UIViewControllerRepresentable {
    let session: PlaybackSession
    let playback: PlaybackCoordinator

    func makeCoordinator() -> PlayerDriver { PlayerDriver(playback: playback) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = context.coordinator.player
        context.coordinator.controller = controller
        context.coordinator.load(session)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.load(session)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: PlayerDriver) {
        coordinator.teardown()
    }
}

/// Owns the AVPlayer: candidate fallback, resume seek, progress saving and the "next episode" action.
@MainActor
final class PlayerDriver: NSObject {
    let player = AVPlayer()
    weak var controller: AVPlayerViewController?

    private let playback: PlaybackCoordinator
    private var session: PlaybackSession?
    private var candidateIndex = 0
    private var lastPosition: Double = 0
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var ticksSinceSave = 0

    private static let tick: Double = 5
    private static let saveEveryTicks = 2
    private static let nextEpisodeLeadTime: Double = 60

    init(playback: PlaybackCoordinator) {
        self.playback = playback
        super.init()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: Self.tick, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.onEnd(note.object as? AVPlayerItem) }
        }
    }

    func load(_ newSession: PlaybackSession) {
        guard newSession.id != session?.id else { return }
        saveProgress()
        session = newSession
        candidateIndex = 0
        lastPosition = newSession.resumePosition ?? 0
        controller?.contextualActions = []
        startCurrentCandidate()
    }

    func teardown() {
        saveProgress()
        player.pause()
        statusObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }

    private func startCurrentCandidate() {
        guard let session, candidateIndex < session.candidates.count,
              let url = session.candidates[candidateIndex].playableURL else {
            player.replaceCurrentItem(with: nil)
            playback.playbackFailed()
            return
        }
        let item = AVPlayerItem(url: url)
        item.externalMetadata = metadata(for: session)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in self?.statusChanged(item) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay where lastPosition > 0 && player.currentTime().seconds < 1:
            // Also restores the position when falling back to another source mid-playback.
            player.seek(to: CMTime(seconds: lastPosition, preferredTimescale: 600))
        case .failed:
            candidateIndex += 1
            startCurrentCandidate()
        default:
            break
        }
    }

    private func onTick() {
        guard let item = player.currentItem, item.status == .readyToPlay else { return }
        lastPosition = player.currentTime().seconds
        ticksSinceSave += 1
        if ticksSinceSave >= Self.saveEveryTicks {
            ticksSinceSave = 0
            saveProgress()
        }
        updateNextEpisodeAction(duration: item.duration.seconds)
    }

    private func updateNextEpisodeAction(duration: Double) {
        guard let controller, let next = session?.nextEpisode, duration.isFinite else { return }
        let nearEnd = duration - lastPosition <= Self.nextEpisodeLeadTime
        if nearEnd, controller.contextualActions.isEmpty {
            let action = UIAction(title: "Épisode suivant · \(next.code)", image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
                Task { @MainActor in await self?.playback.playNextEpisode() }
            }
            controller.contextualActions = [action]
        } else if !nearEnd, !controller.contextualActions.isEmpty {
            controller.contextualActions = []
        }
    }

    private func onEnd(_ item: AVPlayerItem?) {
        guard let item, item === player.currentItem else { return }
        saveProgress()
        if session?.nextEpisode != nil {
            Task { await playback.playNextEpisode() }
        } else {
            playback.close()
        }
    }

    private func saveProgress() {
        guard let item = player.currentItem, item.status == .readyToPlay else { return }
        let position = player.currentTime().seconds
        playback.recordProgress(position: position, duration: item.duration.seconds)
    }

    private func metadata(for session: PlaybackSession) -> [AVMetadataItem] {
        var items = [Self.metadataItem(.commonIdentifierTitle, session.item.name)]
        if let subtitle = session.subtitle {
            items.append(Self.metadataItem(.iTunesMetadataTrackSubTitle, subtitle))
        }
        if let description = session.video?.overview ?? session.item.description {
            items.append(Self.metadataItem(.commonIdentifierDescription, description))
        }
        return items
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}
