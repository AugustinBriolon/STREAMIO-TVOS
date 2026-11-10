import Foundation

/// Playback position of one movie or one episode.
public struct PlaybackProgress: Codable, Hashable, Identifiable, Sendable {
    /// At or above this share of the duration an item counts as watched.
    public static let finishedThreshold = 0.9
    /// Below this many seconds, restarting from the beginning is more useful than resuming.
    public static let minimumResumeSeconds: Double = 30

    public let item: MediaItem
    public let video: VideoItem?
    public var position: Double
    public var duration: Double
    public var updatedAt: Date

    public init(item: MediaItem, video: VideoItem?, position: Double, duration: Double, updatedAt: Date) {
        self.item = item
        self.video = video
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    /// Movie id, or episode id ("tt123:1:3") for series.
    public var id: String { video?.id ?? item.id }

    public var fraction: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    public var isFinished: Bool { fraction >= Self.finishedThreshold }

    public var remainingMinutes: Int? {
        guard duration > 0 else { return nil }
        return max(Int((duration - position) / 60), 1)
    }
}
