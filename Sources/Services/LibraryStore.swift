import Foundation
import Observation

/// Playback position of one movie or one episode.
public struct PlaybackProgress: Codable, Hashable, Identifiable, Sendable {
    public let item: MediaItem
    public let video: VideoItem?
    public var position: Double
    public var duration: Double
    public var updatedAt: Date

    /// Movie id, or episode id ("tt123:1:3") for series.
    public var id: String { video?.id ?? item.id }

    public var fraction: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    public var isFinished: Bool { fraction >= LibraryStore.finishedThreshold }

    public var remainingMinutes: Int? {
        guard duration > 0 else { return nil }
        return max(Int((duration - position) / 60), 1)
    }
}

/// "Ma liste" and watch progress, persisted as JSON in UserDefaults (see ADR 0004).
@MainActor
@Observable
public final class LibraryStore {
    public nonisolated static let finishedThreshold = 0.9
    /// Below this, a restart from the beginning is more useful than a resume.
    public nonisolated static let minimumResumeSeconds: Double = 30
    static let maxProgressEntries = 200

    public private(set) var myList: [MediaItem]
    private var progressByID: [String: PlaybackProgress]

    private let defaults: UserDefaults
    private let now: () -> Date
    static let myListKey = "library.myList.v1"
    static let progressKey = "library.progress.v1"

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        myList = Self.decode([MediaItem].self, from: defaults, key: Self.myListKey) ?? []
        let entries = Self.decode([PlaybackProgress].self, from: defaults, key: Self.progressKey) ?? []
        progressByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 })
    }

    // MARK: My List

    public func isInMyList(_ id: String) -> Bool { myList.contains { $0.id == id } }

    public func toggleMyList(_ item: MediaItem) {
        if isInMyList(item.id) {
            myList.removeAll { $0.id == item.id }
        } else {
            myList.insert(item, at: 0)
        }
        persist(myList, key: Self.myListKey)
    }

    // MARK: Progress

    public func progress(for videoID: String) -> PlaybackProgress? { progressByID[videoID] }

    public func isWatched(_ videoID: String) -> Bool { progressByID[videoID]?.isFinished == true }

    /// Position to seek to when starting `videoID`, nil to start from the beginning.
    public func resumePosition(for videoID: String) -> Double? {
        guard let entry = progressByID[videoID], !entry.isFinished,
              entry.position >= Self.minimumResumeSeconds else { return nil }
        return entry.position
    }

    public func updateProgress(item: MediaItem, video: VideoItem?, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        let entry = PlaybackProgress(item: item, video: video, position: position, duration: duration, updatedAt: now())
        progressByID[entry.id] = entry
        persistProgress()
    }

    /// Queues the next episode in "Reprendre la lecture" once the current one is finished.
    public func queueNextEpisode(item: MediaItem, next: VideoItem) {
        guard progressByID[next.id].map({ !$0.isFinished }) ?? true else { return }
        let existing = progressByID[next.id]
        progressByID[next.id] = PlaybackProgress(
            item: item, video: next,
            position: existing?.position ?? 0, duration: existing?.duration ?? 0, updatedAt: now()
        )
        persistProgress()
    }

    /// Latest unfinished entry per title, newest first.
    public func continueWatching(type: MediaType? = nil) -> [PlaybackProgress] {
        let latestPerTitle = Dictionary(grouping: progressByID.values, by: \.item.id)
            .compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
        return latestPerTitle
            .filter { !$0.isFinished && (type == nil || $0.item.type == type) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The entry "Reprendre" should resume for a title, if any.
    public func resumeEntry(forTitle id: String) -> PlaybackProgress? {
        continueWatching().first { $0.item.id == id }
    }

    // MARK: Persistence

    private func persistProgress() {
        let kept = progressByID.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.maxProgressEntries)
        if kept.count < progressByID.count {
            progressByID = Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0) })
        }
        persist(Array(kept), key: Self.progressKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
