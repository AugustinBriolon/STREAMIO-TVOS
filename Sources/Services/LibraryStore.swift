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
    private var myListUpdatedAt: [String: Date] = [:]
    private var deletedMyListByID: [String: Date] = [:]
    private var deletedProgressByID: [String: Date] = [:]
    public private(set) var profileID: UUID
    /// Incremented on local user mutations so cloud sync schedules a push for both list and progress edits.
    public private(set) var syncRevision: Int = 0

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

    /// Forces a reload for `id` even when it is already the active profile (post-logout guest reset).
    public func adoptProfile(_ id: UUID) {
        profileID = id
        load()
    }

    /// Removes everything stored for a profile (used when the profile is deleted).
    nonisolated static func erase(profileID: UUID, from defaults: UserDefaults) {
        defaults.removeObject(forKey: StorageKey.myList(profileID))
        defaults.removeObject(forKey: StorageKey.progress(profileID))
        defaults.removeObject(forKey: StorageKey.myListTimestamps(profileID))
        defaults.removeObject(forKey: StorageKey.deletedMyList(profileID))
        defaults.removeObject(forKey: StorageKey.deletedProgress(profileID))
    }

    private func load() {
        myList = Self.decode([MediaItem].self, from: defaults, key: StorageKey.myList(profileID)) ?? []
        let entries = Self.decode([PlaybackProgress].self, from: defaults, key: StorageKey.progress(profileID)) ?? []
        progressByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 })
        myListUpdatedAt = Self.decode([String: Date].self, from: defaults, key: StorageKey.myListTimestamps(profileID)) ?? [:]
        deletedMyListByID = Self.decode([String: Date].self, from: defaults, key: StorageKey.deletedMyList(profileID)) ?? [:]
        deletedProgressByID = Self.decode([String: Date].self, from: defaults, key: StorageKey.deletedProgress(profileID)) ?? [:]
    }

    // MARK: My List

    public func isInMyList(_ id: String) -> Bool { myList.contains { $0.id == id } }

    public func isInMyList(anyOf ids: [String]) -> Bool {
        myList.contains { ids.contains($0.id) }
    }

    public func toggleMyList(_ item: MediaItem, aliases: [String] = []) {
        let allIDs = Set([item.id] + aliases)
        let timestamp = now()
        if myList.contains(where: { allIDs.contains($0.id) }) {
            let removedIDs = Set(myList.filter { allIDs.contains($0.id) }.map(\.id)).union(allIDs)
            myList.removeAll { allIDs.contains($0.id) }
            for id in removedIDs {
                myListUpdatedAt.removeValue(forKey: id)
                deletedMyListByID[id] = timestamp
            }
        } else {
            myList.insert(item, at: 0)
            myListUpdatedAt[item.id] = timestamp
            for id in allIDs {
                deletedMyListByID.removeValue(forKey: id)
            }
        }
        persist(myList, key: StorageKey.myList(profileID))
        persist(myListUpdatedAt, key: StorageKey.myListTimestamps(profileID))
        persist(deletedMyListByID, key: StorageKey.deletedMyList(profileID))
        syncRevision &+= 1
    }

    /// A title known to this profile (in its list or its history), for links coming from the Top Shelf.
    public func item(withID id: String) -> MediaItem? {
        myList.first { $0.id == id } ?? progressByID.values.first { $0.item.id == id }?.item
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
        if deletedProgressByID.removeValue(forKey: entry.id) != nil {
            persist(deletedProgressByID, key: StorageKey.deletedProgress(profileID))
        }
        persistProgress()
        syncRevision &+= 1
    }

    /// Queues the next episode in "Reprendre la lecture" once the current one is finished.
    public func queueNextEpisode(item: MediaItem, next: VideoItem) {
        guard progressByID[next.id].map({ !$0.isFinished }) ?? true else { return }
        let existing = progressByID[next.id]
        progressByID[next.id] = PlaybackProgress(
            item: item, video: next,
            position: existing?.position ?? 0, duration: existing?.duration ?? 0, updatedAt: now()
        )
        if deletedProgressByID.removeValue(forKey: next.id) != nil {
            persist(deletedProgressByID, key: StorageKey.deletedProgress(profileID))
        }
        persistProgress()
        syncRevision &+= 1
    }

    /// Drops the resume points of a title (including a queued next episode) but keeps finished
    /// episodes, so "watched" marks survive and the title leaves "Reprendre la lecture".
    public func removeFromContinueWatching(titleID: String) {
        let timestamp = now()
        let removedIDs = progressByID.filter { $0.value.item.id == titleID && !$0.value.isFinished }.keys
        for videoID in removedIDs {
            deletedProgressByID[videoID] = timestamp
        }
        progressByID = progressByID.filter { $0.value.item.id != titleID || $0.value.isFinished }
        persistProgress()
        if !removedIDs.isEmpty {
            persist(deletedProgressByID, key: StorageKey.deletedProgress(profileID))
        }
        syncRevision &+= 1
    }

    /// Latest unfinished entry per title, newest first.
    public func continueWatching(type: MediaType? = nil) -> [PlaybackProgress] {
        let latestPerTitle = Dictionary(grouping: progressByID.values, by: \.item.id)
            .compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
        return latestPerTitle
            .filter { !$0.isFinished && (type == nil || $0.item.type == type) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// All stored progress entries across all items.
    public var allProgress: [PlaybackProgress] {
        Array(progressByID.values)
    }

    /// Timestamp when `itemID` was added to My List locally (used by cloud sync).
    public func myListAddedAt(for itemID: String) -> Date? {
        myListUpdatedAt[itemID]
    }

    /// Tombstones of removed My List items for the active profile.
    public var deletedMyListEntries: [String: Date] { deletedMyListByID }

    /// Tombstones of removed Continue Watching entries for the active profile.
    public var deletedProgressEntries: [String: Date] { deletedProgressByID }

    /// Merges remote items and tombstones into myList without resurrecting deleted entries.
    public func mergeRemote(
        items: [MediaItem],
        remoteTimestamps: [String: Date] = [:],
        remoteDeletions: [String: Date] = [:]
    ) {
        var listChanged = false
        var timestampsChanged = false
        var deletionsChanged = false

        for (id, remoteDel) in remoteDeletions {
            let previousDel = deletedMyListByID[id] ?? .distantPast
            if remoteDel > previousDel {
                deletedMyListByID[id] = remoteDel
                deletionsChanged = true
            }
            let localAdded = myListUpdatedAt[id] ?? .distantPast
            if remoteDel > localAdded, myList.contains(where: { $0.id == id }) {
                myList.removeAll { $0.id == id }
                myListUpdatedAt.removeValue(forKey: id)
                listChanged = true
                timestampsChanged = true
            }
        }

        for item in items {
            let remoteAdded = remoteTimestamps[item.id] ?? .distantPast
            if let localDel = deletedMyListByID[item.id] {
                if remoteAdded > localDel {
                    deletedMyListByID.removeValue(forKey: item.id)
                    deletionsChanged = true
                } else {
                    continue
                }
            }

            if !myList.contains(where: { $0.id == item.id }) {
                myList.append(item)
                listChanged = true
                if remoteAdded > (myListUpdatedAt[item.id] ?? .distantPast) {
                    myListUpdatedAt[item.id] = remoteAdded
                    timestampsChanged = true
                }
            }
        }

        if listChanged {
            persist(myList, key: StorageKey.myList(profileID))
        }
        if timestampsChanged {
            persist(myListUpdatedAt, key: StorageKey.myListTimestamps(profileID))
        }
        if deletionsChanged {
            persist(deletedMyListByID, key: StorageKey.deletedMyList(profileID))
        }
    }

    /// Merges remote progress entries and tombstones, keeping the most recent state.
    public func mergeRemote(
        progress entries: [PlaybackProgress],
        remoteDeletions: [String: Date] = [:]
    ) {
        var progressChanged = false
        var deletionsChanged = false

        for (videoID, remoteDel) in remoteDeletions {
            let previousDel = deletedProgressByID[videoID] ?? .distantPast
            if remoteDel > previousDel {
                deletedProgressByID[videoID] = remoteDel
                deletionsChanged = true
            }
            if let existing = progressByID[videoID], !existing.isFinished, remoteDel > existing.updatedAt {
                progressByID.removeValue(forKey: videoID)
                progressChanged = true
            }
        }

        for entry in entries {
            if let localDel = deletedProgressByID[entry.id] {
                if entry.updatedAt > localDel {
                    deletedProgressByID.removeValue(forKey: entry.id)
                    deletionsChanged = true
                } else {
                    continue
                }
            }

            if let existing = progressByID[entry.id] {
                if entry.updatedAt > existing.updatedAt {
                    progressByID[entry.id] = entry
                    progressChanged = true
                }
            } else {
                progressByID[entry.id] = entry
                progressChanged = true
            }
        }

        if progressChanged {
            persistProgress()
        }
        if deletionsChanged {
            persist(deletedProgressByID, key: StorageKey.deletedProgress(profileID))
        }
    }

    /// The entry "Reprendre" should resume for a title, if any.
    public func resumeEntry(forTitle id: String, aliases: [String] = []) -> PlaybackProgress? {
        let allIDs = Set([id] + aliases)
        return continueWatching().first { allIDs.contains($0.item.id) }
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
