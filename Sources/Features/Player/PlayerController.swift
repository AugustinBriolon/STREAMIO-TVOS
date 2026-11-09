import Foundation
import Observation

/// Session logic around the engine: candidate fallback, "no picture" detection, resume,
/// default tracks, progress saving and next episode.
@MainActor
@Observable
final class PlayerController {
    let engine = VLCPlayerEngine()
    private(set) var session: PlaybackSession?
    private(set) var candidateIndex = 0

    @ObservationIgnored private let playback: PlaybackCoordinator
    @ObservationIgnored private let language: String
    @ObservationIgnored private var appliedDefaultTracks = false
    @ObservationIgnored private var lastSavedAt: Double = 0
    @ObservationIgnored private var monitor: Task<Void, Never>?

    /// A file whose video cannot be decoded plays audio only; give up on it after this much playback.
    static let noPictureTimeout: Double = 6
    static let nextEpisodeLeadTime: Double = 60
    static let saveInterval: Double = 10

    init(playback: PlaybackCoordinator, language: String? = nil) {
        self.playback = playback
        self.language = language ?? Self.deviceLanguage
    }

    nonisolated static var deviceLanguage: String {
        Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "fr"
    }

    var nextEpisode: VideoItem? { session?.nextEpisode }

    var showsNextEpisode: Bool {
        nextEpisode != nil && engine.duration > 0 && engine.duration - engine.currentTime <= Self.nextEpisodeLeadTime
    }

    func load(_ newSession: PlaybackSession) {
        guard newSession.id != session?.id else { return }
        saveProgress(force: true)
        session = newSession
        candidateIndex = 0
        startCandidate(at: newSession.resumePosition)
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func close() {
        saveProgress(force: true)
        monitor?.cancel()
        engine.stop()
        playback.close()
    }

    func playNextEpisode() {
        saveProgress(force: true)
        Task { await playback.playNextEpisode() }
    }

    private func startCandidate(at position: Double?) {
        guard let session, candidateIndex < session.candidates.count,
              let url = session.candidates[candidateIndex].playableURL else {
            monitor?.cancel()
            engine.stop()
            playback.playbackFailed()
            return
        }
        appliedDefaultTracks = false
        lastSavedAt = position ?? 0
        engine.open(url, startAt: position)
    }

    private func fallBackToNextCandidate() {
        let resumeAt = engine.currentTime > 0 ? engine.currentTime : session?.resumePosition
        candidateIndex += 1
        startCandidate(at: resumeAt)
    }

    private func tick() {
        switch engine.phase {
        case .failed:
            fallBackToNextCandidate()
        case .ended:
            saveProgress(force: true)
            nextEpisode == nil ? close() : playNextEpisode()
        case .playing:
            if engine.playedSeconds >= Self.noPictureTimeout && !engine.hasVideoOutput {
                fallBackToNextCandidate()
                return
            }
            applyDefaultTracksIfNeeded()
            saveProgress(force: false)
        default:
            break
        }
    }

    private func applyDefaultTracksIfNeeded() {
        guard !appliedDefaultTracks, !engine.audioTracks.isEmpty else { return }
        appliedDefaultTracks = true
        let audio = TrackSelector.preferredAudio(engine.audioTracks, language: language)
        if let audio, audio.id != engine.selectedAudioID { engine.selectAudio(audio.id) }
        let subtitle = TrackSelector.preferredSubtitle(engine.subtitleTracks, audio: audio, language: language)
        engine.selectSubtitle(subtitle?.id ?? -1)
    }

    private func saveProgress(force: Bool) {
        guard engine.duration > 0, engine.currentTime > 0 else { return }
        guard force || abs(engine.currentTime - lastSavedAt) >= Self.saveInterval else { return }
        lastSavedAt = engine.currentTime
        playback.recordProgress(position: engine.currentTime, duration: engine.duration)
    }
}
