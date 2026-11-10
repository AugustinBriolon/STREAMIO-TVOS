import Foundation
import Testing
@testable import StremioTV

struct TopShelfTests {
    private func progress(_ item: MediaItem, video: VideoItem? = nil, position: Double, duration: Double = 6000, at seconds: TimeInterval) -> PlaybackProgress {
        PlaybackProgress(item: item, video: video, position: position, duration: duration, updatedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func resumeComesFirstNewestFirstOncePerTitle() {
        let sections = TopShelfSection.make(progress: [
            progress(movie("tt1", "Ancien"), position: 600, at: 10),
            progress(show("tt2", "Série"), video: episode(1, 1, show: "tt2"), position: 600, duration: 2400, at: 20),
            progress(show("tt2", "Série"), video: episode(1, 2, show: "tt2"), position: 300, duration: 2400, at: 30),
            progress(movie("tt3", "Fini"), position: 5900, at: 40),
        ], myList: [])
        #expect(sections.map(\.kind) == [.continueWatching])
        let entries = sections[0].entries
        #expect(entries.map(\.title) == ["Série · S1:É2 · Ep 2", "Ancien"])
        #expect(entries[0].progress == 0.125)
        #expect(entries[0].playLink == .resume("tt2:1:2"))   // Play resumes the episode
        #expect(entries[0].displayLink == .details("tt2"))   // selecting shows the series page
        #expect(!entries[0].isPoster)
    }

    @Test func myListFollowsWithoutTitlesAlreadyBeingResumed() {
        let sections = TopShelfSection.make(
            progress: [progress(movie("tt1", "En cours"), position: 600, at: 1)],
            myList: [movie("tt1", "En cours"), movie("tt2", "À voir")]
        )
        #expect(sections.map(\.title) == ["Reprendre la lecture", "Ma liste"])
        #expect(sections[1].entries.map(\.title) == ["À voir"])
        #expect(sections[1].entries[0].isPoster)
        #expect(sections[1].entries[0].progress == nil)
        #expect(sections[1].entries[0].playLink == .play("tt2"))
    }

    @Test func emptySectionsAreDroppedAndSectionsAreCapped() {
        #expect(TopShelfSection.make(progress: [], myList: []).isEmpty)
        let onlyList = TopShelfSection.make(progress: [], myList: (0..<25).map { movie("tt\($0)") })
        #expect(onlyList.map(\.kind) == [.myList])
        #expect(onlyList[0].entries.count == TopShelfSection.limit)
    }

    @Test func queuedNextEpisodeHasNoProgressBar() {
        let queued = progress(show("tt2"), video: episode(1, 2, show: "tt2"), position: 0, duration: 0, at: 1)
        #expect(TopShelfSection.make(progress: [queued], myList: [])[0].entries[0].progress == nil)
    }

    @Test func readsTheActiveProfilesData() throws {
        let defaults = makeDefaults()
        let a = UUID(), b = UUID()
        defaults.set(try JSONEncoder().encode([progress(movie("tt1", "De A"), position: 600, at: 1)]), forKey: StorageKey.progress(a))
        defaults.set(try JSONEncoder().encode([movie("tt2", "Liste de B")]), forKey: StorageKey.myList(b))

        defaults.set(b.uuidString, forKey: StorageKey.activeProfile)
        #expect(TopShelfSection.load(defaults: defaults).flatMap(\.entries).map(\.title) == ["Liste de B"])
        defaults.set(a.uuidString, forKey: StorageKey.activeProfile)
        #expect(TopShelfSection.load(defaults: defaults).flatMap(\.entries).map(\.title) == ["De A"])
        defaults.removeObject(forKey: StorageKey.activeProfile)
        #expect(TopShelfSection.load(defaults: defaults).isEmpty)
    }

    @Test func linksRoundTrip() {
        for link in [TopShelfLink.resume("tt123:1:3"), .play("tt123"), .details("tt123")] {
            #expect(TopShelfLink(url: link.url) == link)
        }
        #expect(TopShelfLink(url: URL(string: "stremiotv://other?id=x")!) == nil)
        #expect(TopShelfLink(url: URL(string: "https://play?id=x")!) == nil)
        #expect(TopShelfLink(url: URL(string: "stremiotv://play")!) == nil)
    }
}

@MainActor
struct LibraryLookupTests {
    @Test func findsTitlesFromTheListOrTheHistory() {
        let library = LibraryStore(profileID: UUID(), defaults: makeDefaults())
        library.toggleMyList(movie("tt1"))
        library.updateProgress(item: show("tt2"), video: episode(1, 1, show: "tt2"), position: 100, duration: 2400)
        #expect(library.item(withID: "tt1")?.id == "tt1")
        #expect(library.item(withID: "tt2")?.type == .series)
        #expect(library.item(withID: "tt9") == nil)
    }
}
