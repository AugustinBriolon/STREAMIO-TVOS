import Foundation
import Observation

/// "Ma liste" and watch progress of one profile, persisted as JSON in the shared UserDefaults (ADR 0004, 0014).
@MainActor
@Observable
public final class LibraryStore {
    public nonisolated static let finishedThreshold = PlaybackProgress.finishedThreshold
    public nonisolated static let minimumResumeSeconds = PlaybackProgress.minimumResumeSeconds
    static let maxProgressEntries = 200
    /// Profile used when none is given (unit tests).
    nonisolated static let defaultProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public private(set) var myList: [MediaItem] = []
    private var progressByID: [String: PlaybackProgress] = [:]
    public private(set) var profileID: UUID

    private let defaults: UserDefaults
    private let now: () -> Date

    init(profileID: UUID = LibraryStore.defaultProfileID, defaults: UserDefaults = AppGroup.defaults,
                now: @escaping () -> Date = Date.init) {
        self.profileID = profileID
        self.defaults = defaults
        self.now = now
        load()
    }

    /// Switches to another profile's list and progress.
    public func switchProfile(to id: UUID) {
        guard id != profileID else { return }
        profileID = id
        load()
    }

    /// Removes everything stored for a profile (used when the profile is deleted).
    nonisolated static func erase(profileID: UUID, from defaults: UserDefaults) {
        defaults.removeObject(forKey: StorageKey.myList(profileID))
        defaults.removeObject(forKey: StorageKey.progress(profileID))
    }

    private func load() {
        myList = Self.decode([MediaItem].self, from: defaults, key: StorageKey.myList(profileID)) ?? []
        let entries = Self.decode([PlaybackProgress].self, from: defaults, key: StorageKey.progress(profileID)) ?? []
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
        persist(myList, key: StorageKey.myList(profileID))
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

    /// Drops the resume points of a title (including a queued next episode) but keeps finished
    /// episodes, so "watched" marks survive and the title leaves "Reprendre la lecture".
    public func removeFromContinueWatching(titleID: String) {
        progressByID = progressByID.filter { $0.value.item.id != titleID || $0.value.isFinished }
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
        persist(Array(kept), key: StorageKey.progress(profileID))
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
