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

    @ObservationIgnored let videoView = UIView()
    @ObservationIgnored private(set) var currentURL: URL?
    @ObservationIgnored private let player = VLCMediaPlayer()
    @ObservationIgnored private var lastTimeSample: Double?

    override init() {
        super.init()
        videoView.backgroundColor = .black
        player.drawable = videoView
        player.delegate = self
    }

    var hasVideoOutput: Bool { player.hasVideoOut }

    func open(_ url: URL, startAt seconds: Double?) {
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

    func selectAudio(_ id: Int32) {
        player.currentAudioTrackIndex = id
        selectedAudioID = id
    }

    func selectSubtitle(_ id: Int32) {
        player.currentVideoSubTitleIndex = id
        selectedSubtitleID = id
    }

    private func refreshTracks() {
        audioTracks = Self.tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes)
        subtitleTracks = Self.tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes)
        selectedAudioID = player.currentAudioTrackIndex
        selectedSubtitleID = player.currentVideoSubTitleIndex
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
            refreshTracks()
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
        if let length = player.media?.length.intValue, length > 0 {
            duration = Double(length) / 1000
        }
        if phase == .opening { phase = .playing }
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
