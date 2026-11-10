import Foundation
import Testing
@testable import StremioTV

struct TopShelfTests {
    private func progress(_ item: MediaItem, video: VideoItem? = nil, position: Double, duration: Double = 6000, at seconds: TimeInterval) -> PlaybackProgress {
        PlaybackProgress(item: item, video: video, position: position, duration: duration, updatedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func listsUnfinishedTitlesNewestFirstOncePerTitle() {
        let entries = TopShelfEntry.make(from: [
            progress(movie("tt1", "Ancien"), position: 600, at: 10),
            progress(show("tt2", "Série"), video: episode(1, 1, show: "tt2"), position: 600, duration: 2400, at: 20),
            progress(show("tt2", "Série"), video: episode(1, 2, show: "tt2"), position: 300, duration: 2400, at: 30),
            progress(movie("tt3", "Fini"), position: 5900, at: 40),
        ])
        #expect(entries.map(\.title) == ["Série", "Ancien"])
        #expect(entries.first?.id == "tt2:1:2")
        #expect(entries.first?.subtitle == "S1:É2 · Ep 2")
        #expect(entries.first?.progress == 0.125)
    }

    @Test func capsTheNumberOfItems() {
        let many = (0..<25).map { progress(movie("tt\($0)"), position: 600, at: Double($0)) }
        #expect(TopShelfEntry.make(from: many).count == TopShelfEntry.limit)
    }

    @Test func readsTheActiveProfilesProgress() throws {
        let defaults = makeDefaults()
        let a = UUID(), b = UUID()
        defaults.set(try JSONEncoder().encode([progress(movie("tt1", "De A"), position: 600, at: 1)]), forKey: StorageKey.progress(a))
        defaults.set(try JSONEncoder().encode([progress(movie("tt2", "De B"), position: 600, at: 1)]), forKey: StorageKey.progress(b))

        defaults.set(b.uuidString, forKey: StorageKey.activeProfile)
        #expect(TopShelfEntry.load(defaults: defaults).map(\.title) == ["De B"])
        defaults.set(a.uuidString, forKey: StorageKey.activeProfile)
        #expect(TopShelfEntry.load(defaults: defaults).map(\.title) == ["De A"])
        defaults.removeObject(forKey: StorageKey.activeProfile)
        #expect(TopShelfEntry.load(defaults: defaults).isEmpty)
    }

    @Test func linksRoundTrip() {
        for id in ["tt123", "tt123:1:3"] {
            #expect(TopShelfLink.progressID(from: TopShelfLink.play(id)) == id)
        }
        #expect(TopShelfLink.progressID(from: URL(string: "stremiotv://other?id=x")!) == nil)
        #expect(TopShelfLink.progressID(from: URL(string: "https://play?id=x")!) == nil)
        #expect(TopShelfLink.progressID(from: URL(string: "stremiotv://play")!) == nil)
    }
}
