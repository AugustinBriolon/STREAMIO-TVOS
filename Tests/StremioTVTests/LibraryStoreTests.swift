import Foundation
import Testing
@testable import StremioTV

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
}
