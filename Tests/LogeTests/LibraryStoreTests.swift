import Foundation
import Testing
@testable import Loge

@MainActor
struct LibraryStoreTests {
    let defaults = makeDefaults()
    let clock = TestClock()

    private func makeStore() -> LibraryStore { LibraryStore(defaults: defaults, now: clock.now) }

    @Test func togglesMyListAndPersists() {
        let store = makeStore()
        store.toggleMyList(movie("tt1"))
        #expect(store.isInMyList("tt1"))
        #expect(makeStore().isInMyList("tt1"))
        store.toggleMyList(movie("tt1"))
        #expect(!store.isInMyList("tt1"))
    }

    @Test func togglesMyListAcrossTMDBAndIMDbAliases() {
        let store = makeStore()
        let preResolved = movie("tmdb:12345")
        let canonical = movie("tt9999999")
        let aliases = ["tmdb:12345", "tt9999999"]

        // Added before resolution under TMDB ID
        store.toggleMyList(preResolved, aliases: aliases)
        #expect(store.isInMyList(anyOf: aliases))

        // Toggling with canonical IMDb item removes the TMDB entry instead of duplicating
        store.toggleMyList(canonical, aliases: aliases)
        #expect(!store.isInMyList(anyOf: aliases))
        #expect(store.myList.isEmpty)

        // Added after resolution under IMDb ID: a page opened from the TMDB catalog item still finds it,
        // because it looks the title up with every id it knows (`DetailViewModel.idAliases`).
        store.toggleMyList(canonical, aliases: aliases)
        #expect(store.isInMyList(anyOf: aliases))
        #expect(store.isInMyList("tt9999999"))
        #expect(!store.isInMyList("tmdb:12345"))
        #expect(store.myList.count == 1)
    }

    @Test func resumesOnlyBetweenThresholds() {
        let store = makeStore()
        store.updateProgress(item: movie("a"), video: nil, position: 10, duration: 6000)
        store.updateProgress(item: movie("b"), video: nil, position: 1200, duration: 6000)
        store.updateProgress(item: movie("c"), video: nil, position: 5900, duration: 6000)
        #expect(store.resumePosition(for: "a") == nil)
        #expect(store.resumePosition(for: "b") == 1200)
        #expect(store.resumePosition(for: "c") == nil)
        #expect(store.isWatched("c"))
        #expect(store.continueWatching().map(\.item.id) == ["b", "a"])
    }

    @Test func continueWatchingShowsLatestEpisodePerShow() {
        let store = makeStore()
        let series = show("tt1")
        store.updateProgress(item: series, video: episode(1, 1), position: 2000, duration: 2400)
        store.queueNextEpisode(item: series, next: episode(1, 2))
        let entries = store.continueWatching(type: .series)
        #expect(entries.count == 1)
        #expect(entries.first?.video?.id == "tt1:1:2")
        #expect(store.continueWatching(type: .movie).isEmpty)
    }

    @Test func ignoresInvalidDurations() {
        let store = makeStore()
        store.updateProgress(item: movie("a"), video: nil, position: 10, duration: .nan)
        store.updateProgress(item: movie("a"), video: nil, position: 10, duration: 0)
        #expect(store.progress(for: "a") == nil)
    }

    @Test func capsHistory() {
        let store = makeStore()
        for index in 0..<(LibraryStore.maxProgressEntries + 5) {
            store.updateProgress(item: movie("m\(index)"), video: nil, position: 100, duration: 1000)
        }
        #expect(store.progress(for: "m0") == nil)
        #expect(store.progress(for: "m204") != nil)
        #expect(makeStore().continueWatching().count == LibraryStore.maxProgressEntries)
    }

    @Test func resumeButtonTitles() {
        let entry = PlaybackProgress(item: show("tt1"), video: episode(2, 3), position: 600, duration: 2400, updatedAt: .now)
        #expect(entry.resumeButtonTitle == "Reprendre S2:É3")
        #expect(entry.remainingLabel == "30 min restantes")
        let queued = PlaybackProgress(item: show("tt1"), video: episode(2, 4), position: 0, duration: 0, updatedAt: .now)
        #expect(queued.resumeButtonTitle == "Lecture S2:É4")
        #expect(queued.remainingLabel == nil)
    }
}

@MainActor
struct ContinueWatchingRemovalTests {
    @Test func removingATitleKeepsWatchedEpisodes() {
        let store = LibraryStore(defaults: makeDefaults(), now: TestClock().now)
        let series = show("tt1")
        store.updateProgress(item: series, video: episode(1, 1), position: 2390, duration: 2400)
        store.queueNextEpisode(item: series, next: episode(1, 2))
        store.updateProgress(item: movie("m1"), video: nil, position: 600, duration: 6000)

        store.removeFromContinueWatching(titleID: "tt1")

        #expect(store.continueWatching().map(\.item.id) == ["m1"])
        #expect(store.isWatched("tt1:1:1"))
        #expect(store.progress(for: "tt1:1:2") == nil)
        #expect(store.resumeEntry(forTitle: "tt1") == nil)
    }

    @Test func deletedMyListSurvivesRemoteMergeUntilReAdded() {
        let defaults = makeDefaults()
        let clock = TestClock()
        let store = LibraryStore(defaults: defaults, now: clock.now)
        let item = movie("tt1")

        store.toggleMyList(item)
        let tAdd = store.myListAddedAt(for: "tt1")!
        store.toggleMyList(item)
        let tDel = store.deletedMyListEntries["tt1"]!
        #expect(!store.isInMyList("tt1"))
        #expect(tDel > tAdd)

        // Remote pull still holding the older copy must NOT resurrect it.
        store.mergeRemote(items: [item], remoteTimestamps: ["tt1": tAdd], remoteDeletions: [:])
        #expect(!store.isInMyList("tt1"))

        // Re-adding later clears the tombstone and survives remote old deletion tombstones.
        store.toggleMyList(item)
        store.mergeRemote(items: [], remoteTimestamps: [:], remoteDeletions: ["tt1": tDel])
        #expect(store.isInMyList("tt1"))
    }

    @Test func deletedProgressSurvivesRemoteMergeAndAppliesRemoteTombstone() {
        let defaults = makeDefaults()
        let clock = TestClock()
        let store = LibraryStore(defaults: defaults, now: clock.now)
        let item = movie("m1")

        store.updateProgress(item: item, video: nil, position: 500, duration: 5000)
        let tWatch = store.progress(for: "m1")!.updatedAt
        let revisionBeforeDelete = store.syncRevision
        store.removeFromContinueWatching(titleID: "m1")
        let tDelete = store.deletedProgressEntries["m1"]!
        #expect(store.syncRevision > revisionBeforeDelete)
        #expect(store.continueWatching().isEmpty)

        // Older remote progress must NOT resurrect the deleted entry.
        let staleRemote = PlaybackProgress(item: item, video: nil, position: 500, duration: 5000, updatedAt: tWatch)
        store.mergeRemote(progress: [staleRemote], remoteDeletions: [:])
        #expect(store.continueWatching().isEmpty)

        // Re-watching later survives an older remote tombstone, while a newer remote tombstone removes it.
        store.updateProgress(item: item, video: nil, position: 800, duration: 5000)
        let tRewatch = store.progress(for: "m1")!.updatedAt
        store.mergeRemote(progress: [], remoteDeletions: ["m1": tDelete])
        #expect(store.continueWatching().count == 1)

        let tRemoteDelete = clock.now()
        #expect(tRemoteDelete > tRewatch)
        store.mergeRemote(progress: [], remoteDeletions: ["m1": tRemoteDelete])
        #expect(store.continueWatching().isEmpty)
    }
}

struct FocusNeighborTests {
    @Test func picksRightNeighborWhenRemovingFirstOrMiddleItem() {
        #expect(FocusNeighbor.nearestRemainingID(in: ["a", "b", "c"], removing: "a") == "b")
        #expect(FocusNeighbor.nearestRemainingID(in: ["a", "b", "c"], removing: "b") == "c")
    }

    @Test func picksLeftNeighborWhenRemovingLastItem() {
        #expect(FocusNeighbor.nearestRemainingID(in: ["a", "b", "c"], removing: "c") == "b")
    }

    @Test func returnsNilWhenRemovingOnlyRemainingItem() {
        #expect(FocusNeighbor.nearestRemainingID(in: ["a"], removing: "a") == nil)
    }

    @Test func handlesReturningAfterMultipleRemovalsAcrossNavigation() {
        #expect(FocusNeighbor.nearestRemaining(oldIDs: ["a", "b", "c", "d"], newIDs: ["a", "d"], removedID: "b") == "d")
        #expect(FocusNeighbor.nearestRemaining(oldIDs: ["a", "b", "c"], newIDs: ["a"], removedID: "c") == "a")
    }
}
