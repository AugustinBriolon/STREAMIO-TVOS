import Foundation
import Testing
@testable import Loge

struct PlaybackSourcePolicyTests {
    @Test func defaultsAloneStillGetTrailer() {
        let trailer = StreamItem.youtubeTrailer(videoKey: "abc", streamURL: URL(string: "https://cdn/t.mp4")!)
        let resolved = PlaybackSourcePolicy.streams(
            addonURLs: AddonStore.defaultAddonURLs,
            fromAddons: [],
            trailer: trailer
        )
        #expect(resolved.map(\.id) == [trailer.id])
        #expect(!PlaybackSourcePolicy.hasPersonalAddons(AddonStore.defaultAddonURLs))
    }

    @Test func personalAddonsNeverInjectTrailer() {
        let trailer = StreamItem.youtubeTrailer(videoKey: "abc", streamURL: URL(string: "https://cdn/t.mp4")!)
        let playable = stream("RD+", url: "https://cdn/ok")
        let urls = AddonStore.defaultAddonURLs + ["https://addon.test"]
        let resolved = PlaybackSourcePolicy.streams(
            addonURLs: urls,
            fromAddons: [playable],
            trailer: trailer
        )
        #expect(resolved.map(\.url) == ["https://cdn/ok"])
        #expect(resolved.allSatisfy { !$0.isYouTubeTrailer })
        #expect(PlaybackSourcePolicy.hasPersonalAddons(urls))
    }

    @Test func emptyListWithoutTrailerYieldEmpty() {
        let resolved = PlaybackSourcePolicy.streams(addonURLs: [], fromAddons: [], trailer: nil)
        #expect(resolved.isEmpty)
    }
}
