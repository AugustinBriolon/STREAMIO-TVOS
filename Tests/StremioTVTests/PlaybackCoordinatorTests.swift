import Foundation
import Testing
@testable import StremioTV

@MainActor
struct PlaybackCoordinatorTests {
    let library = LibraryStore(defaults: makeDefaults(), now: TestClock().now)

    private func makeCoordinator(_ service: StubService, addons urls: [String] = ["https://addon"]) -> PlaybackCoordinator {
        let addons = AddonStore(storage: InMemorySecretStorage(urls), legacyDefaults: makeDefaults())
        return PlaybackCoordinator(service: service, addons: addons, library: library, device: .all)
    }

    @Test func explainsMissingAddons() async {
        let coordinator = makeCoordinator(StubService(), addons: [])
        await coordinator.play(item: movie("tt9"))
        #expect(coordinator.session == nil)
        #expect(coordinator.errorMessage?.contains("addon") == true)
    }

    @Test func picksBestPlayableStreamsAndResumePoint() async {
        var service = StubService()
        service.streams["tt9"] = [stream("T", "2160p", url: nil, infoHash: "h"), stream("[RD+]", "1080p", url: "https://ok")]
        library.updateProgress(item: movie("tt9"), video: nil, position: 900, duration: 6000)
        let coordinator = makeCoordinator(service)
        await coordinator.play(item: movie("tt9"))
        #expect(coordinator.session?.candidates.map(\.url) == ["https://ok"])
        #expect(coordinator.session?.resumePosition == 900)
    }

    @Test func resolvingTitleIsClearedOnceThePlayIsSettled() async {
        var service = StubService()
        service.streams["tt9"] = [stream("[RD+]", "1080p", url: "https://ok")]
        let coordinator = makeCoordinator(service)
        #expect(!coordinator.isResolving)
        await coordinator.play(item: movie("tt9"))
        #expect(coordinator.resolvingItem == nil)
        await coordinator.play(item: movie("tt404"))
        #expect(coordinator.resolvingItem == nil)
    }

    @Test func reportsWhenNothingIsPlayable() async {
        var service = StubService()
        service.streams["tt9"] = [stream("T", url: nil, infoHash: "h")]
        let coordinator = makeCoordinator(service)
        await coordinator.play(item: movie("tt9"))
        #expect(coordinator.session == nil)
        #expect(coordinator.errorMessage != nil)
    }

    @Test func seriesResumeTheWatchedEpisodeAndQueueTheNextOne() async {
        let series = show("tt1")
        var service = StubService()
        service.details["tt1"] = MediaDetail(id: "tt1", name: "Série", type: .series, videos: [episode(1, 1), episode(1, 2)])
        service.streams["tt1:1:1"] = [stream("[RD+]", url: "https://e1")]
        service.streams["tt1:1:2"] = [stream("[RD+]", url: "https://e2")]
        library.updateProgress(item: series, video: episode(1, 1), position: 120, duration: 2400)

        let coordinator = makeCoordinator(service)
        await coordinator.play(item: series)
        #expect(coordinator.session?.video?.id == "tt1:1:1")
        #expect(coordinator.session?.nextEpisode?.id == "tt1:1:2")

        coordinator.recordProgress(position: 2300, duration: 2400)
        #expect(library.resumeEntry(forTitle: "tt1")?.video?.id == "tt1:1:2")

        await coordinator.playNextEpisode()
        #expect(coordinator.session?.candidates.first?.url == "https://e2")
    }

    @Test func preferredStreamBypassesRanking() async {
        let coordinator = makeCoordinator(StubService())
        await coordinator.play(item: movie("tt9"), preferred: stream("Manual", url: "https://manual"))
        #expect(coordinator.session?.candidates.map(\.url) == ["https://manual"])
    }
}
