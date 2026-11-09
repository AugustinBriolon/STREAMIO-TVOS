import Testing
@testable import StremioTV

struct EpisodeNavigationTests {
    let episodes = [episode(2, 1), episode(0, 1), episode(1, 2), episode(1, 1)]

    @Test func ordersSeasonsWithSpecialsLast() {
        #expect(episodes.inWatchOrder.map(\.id) == ["tt1:1:1", "tt1:1:2", "tt1:2:1", "tt1:0:1"])
        #expect(episodes.firstEpisode?.id == "tt1:1:1")
    }

    @Test func nextEpisodeCrossesSeasonsButNotIntoSpecials() {
        #expect(episodes.episode(after: episode(1, 2))?.id == "tt1:2:1")
        #expect(episodes.episode(after: episode(2, 1)) == nil)
    }

    @Test func showsWithOnlySpecialsStillHaveAFirstEpisode() {
        #expect([episode(0, 1)].firstEpisode?.id == "tt1:0:1")
    }
}
