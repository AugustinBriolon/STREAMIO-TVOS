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
    @ObservationIgnored private var probe = PlaybackProbe()

    /// libVLC network buffer in milliseconds: the wait before playback starts, traded against stalls.
    static let networkCaching = 4000
    /// Debug builds can override it at launch (`STREMIO_NETWORK_CACHING`) to compare values on the
    /// same stream without rebuilding.
    private static var effectiveNetworkCaching: Int {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["STREMIO_NETWORK_CACHING"].flatMap(Int.init) { return override }
        #endif
        return networkCaching
    }

    override init() {
        super.init()
        videoView.backgroundColor = .black
        player.drawable = videoView
        player.delegate = self
    }

    var hasVideoOutput: Bool { player.hasVideoOut }

    func open(_ url: URL, startAt seconds: Double?, audioSlaveURL: URL? = nil) {
        didNotifyPlaying = false
        currentURL = url
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=\(Self.effectiveNetworkCaching)")
        // googlevideo URLs (YouTube trailers) reject empty/odd UAs.
        let isGoogleVideo = url.host?.contains("googlevideo.com") == true
            || audioSlaveURL?.host?.contains("googlevideo.com") == true
        if isGoogleVideo {
            media.addOption(":http-user-agent=com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip")
        }
        // Adaptive YouTube: video-only MP4 + AAC companion via input-slave (`#` forces URL parse).
        if let audioSlaveURL {
            media.addOption(":input-slave=#\(audioSlaveURL.absoluteString)")
        }
        probe.opened(at: Date())
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
        probe.clockInterrupted()
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
        let metadata = Self.trackMetadataMap(from: player.media?.tracksInformation)
        let audio = Self.tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes, metadata: metadata)
        let subtitles = Self.tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes, metadata: metadata)
        if audio != audioTracks { audioTracks = audio }
        if subtitles != subtitleTracks { subtitleTracks = subtitles }
        if selectedAudioID != player.currentAudioTrackIndex { selectedAudioID = player.currentAudioTrackIndex }
        if selectedSubtitleID != player.currentVideoSubTitleIndex { selectedSubtitleID = player.currentVideoSubTitleIndex }
    }

    private static func trackMetadataMap(from info: [Any]?) -> [Int32: (language: String?, description: String?)] {
        guard let dicts = info as? [[String: Any]] else { return [:] }
        var map: [Int32: (language: String?, description: String?)] = [:]
        for dict in dicts {
            guard let id = (dict[VLCMediaTracksInformationId] as? NSNumber)?.int32Value else { continue }
            let lang = dict[VLCMediaTracksInformationLanguage] as? String
            let desc = dict[VLCMediaTracksInformationDescription] as? String
            map[id] = (lang, desc)
        }
        return map
    }

    private static func tracks(
        names: [Any],
        indexes: [Any],
        metadata: [Int32: (language: String?, description: String?)]
    ) -> [MediaTrack] {
        zip(indexes, names).compactMap { index, name in
            guard let id = (index as? NSNumber)?.int32Value, var finalName = name as? String else { return nil }
            // Si VLC n'a pas inclus la langue entre crochets, enrichir depuis tracksInformation
            if id >= 0, finalName.range(of: #"\[[^\]]+\]\s*$"#, options: .regularExpression) == nil,
               let langRaw = metadata[id]?.language,
               let localized = TrackDisplay.localizedLanguageName(langRaw) {
                finalName = "\(finalName) - [\(localized)]"
            }
            return MediaTrack(id: id, name: finalName)
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
            probe.clockInterrupted()
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
        measure()
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

    /// Feeds the probe and, in debug builds, prints its findings (never the stream URL: it embeds a key).
    private func measure() {
        let hadStarted = probe.startup != nil
        let stall = probe.tick(at: Date())
        #if DEBUG
        if !hadStarted, let startup = probe.startup {
            print("[probe] caching=\(Self.effectiveNetworkCaching) startup=\(String(format: "%.2f", startup))s")
        }
        if let stall {
            print("[probe] caching=\(Self.effectiveNetworkCaching) stall=\(String(format: "%.2f", stall))s total=\(probe.stalls)")
        }
        #endif
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
