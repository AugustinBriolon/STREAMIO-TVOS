import Foundation
import Observation
import TVVLCKit
import UIKit

/// libVLC-backed engine: plays Matroska, DTS/TrueHD and embedded SRT/PGS subtitles that AVPlayer cannot (see ADR 0007).
@MainActor
@Observable
final class VLCPlayerEngine: NSObject {
    enum Phase: Equatable { case idle, opening, playing, paused, ended, failed }

    private(set) var phase: Phase = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var selectedAudioID: Int32 = -1
    private(set) var selectedSubtitleID: Int32 = -1
    /// Seconds of actual playback since the media opened; used to detect "sound but no picture".
    private(set) var playedSeconds: Double = 0

    /// Called once the engine reports it is playing and the track lists are known.
    @ObservationIgnored var onPlaying: (() -> Void)?
    @ObservationIgnored let videoView = UIView()
    @ObservationIgnored private(set) var currentURL: URL?
    @ObservationIgnored private let player = VLCMediaPlayer()
    @ObservationIgnored private var lastTimeSample: Double?
    @ObservationIgnored private var didNotifyPlaying = false

    override init() {
        super.init()
        videoView.backgroundColor = .black
        player.drawable = videoView
        player.delegate = self
    }

    var hasVideoOutput: Bool { player.hasVideoOut }

    func open(_ url: URL, startAt seconds: Double?) {
        didNotifyPlaying = false
        currentURL = url
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=4000")
        if let seconds, seconds > 0 { media.addOption(":start-time=\(Int(seconds))") }
        currentTime = seconds ?? 0
        duration = 0
        playedSeconds = 0
        lastTimeSample = nil
        audioTracks = []
        subtitleTracks = []
        phase = .opening
        player.media = media
        player.play()
    }

    func stop() {
        player.stop()
        phase = .idle
    }

    func togglePlayPause() {
        player.isPlaying ? player.pause() : player.play()
    }

    func play() { player.play() }

    func pause() { if player.isPlaying { player.pause() } }

    func seek(to seconds: Double) {
        guard player.isSeekable else { return }
        let target = max(0, min(seconds, max(duration - 1, 0)))
        player.time = VLCTime(int: Int32(target * 1000))
        currentTime = target
    }

    /// Switching the audio track makes libVLC drop about 8 video frames while it restarts the decoder
    /// (measured on Apple TV HD). Doing it while paused turns that stutter into a short, intentional pause.
    func selectAudio(_ id: Int32) {
        selectedAudioID = id
        guard player.isPlaying else {
            player.currentAudioTrackIndex = id
            return
        }
        player.pause()
        player.currentAudioTrackIndex = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            // A newer switch schedules its own resume.
            if selectedAudioID == id { player.play() }
        }
    }

    func selectSubtitle(_ id: Int32) {
        player.currentVideoSubTitleIndex = id
        selectedSubtitleID = id
    }

    private func refreshTracks() {
        // @Observable notifies on every assignment, even of an equal value: only publish real changes.
        let audio = Self.tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes)
        let subtitles = Self.tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes)
        if audio != audioTracks { audioTracks = audio }
        if subtitles != subtitleTracks { subtitleTracks = subtitles }
        if selectedAudioID != player.currentAudioTrackIndex { selectedAudioID = player.currentAudioTrackIndex }
        if selectedSubtitleID != player.currentVideoSubTitleIndex { selectedSubtitleID = player.currentVideoSubTitleIndex }
    }

    private static func tracks(names: [Any], indexes: [Any]) -> [MediaTrack] {
        zip(indexes, names).compactMap { index, name in
            guard let id = (index as? NSNumber)?.int32Value, let name = name as? String else { return nil }
            return MediaTrack(id: id, name: name)
        }
    }

    fileprivate func stateChanged() {
        switch player.state {
        case .opening, .buffering:
            if phase == .idle { phase = .opening }
        case .playing:
            phase = .playing
            markPlaying()
        case .paused:
            phase = .paused
        case .ended:
            phase = .ended
        case .error:
            phase = .failed
        case .esAdded:
            refreshTracks()
        case .stopped:
            break
        @unknown default:
            break
        }
    }

    fileprivate func timeChanged() {
        let seconds = Double(player.time.intValue) / 1000
        if let lastTimeSample, seconds > lastTimeSample, seconds - lastTimeSample < 5 {
            playedSeconds += seconds - lastTimeSample
        }
        lastTimeSample = seconds
        currentTime = seconds
        if let length = player.media?.length.intValue, length > 0, duration != Double(length) / 1000 {
            duration = Double(length) / 1000
        }
        if phase == .opening {
            phase = .playing
            markPlaying()
        }
    }

    /// First moment the media is really playing (VLC says so, or its clock starts moving): tracks are known.
    private func markPlaying() {
        refreshTracks()
        guard !didNotifyPlaying else { return }
        didNotifyPlaying = true
        onPlaying?()
    }
}

extension VLCPlayerEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in self.stateChanged() }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in self.timeChanged() }
    }
}
