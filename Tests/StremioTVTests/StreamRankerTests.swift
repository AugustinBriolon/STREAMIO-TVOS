import Testing
@testable import StremioTV

struct StreamRankerTests {
    @Test func ranksDebridThenQuality() {
        let ranked = StreamRanker.rank([
            stream("Torrentio", "1080p", url: "https://a"),
            stream("[RD+] Torrentio", "720p", url: "https://b"),
            stream("[RD+] Torrentio", "2160p", url: "https://c"),
            stream("[RD+] Torrentio", "1080p", url: "https://d"),
        ])
        #expect(ranked.map(\.url) == ["https://c", "https://d", "https://b", "https://a"])
    }

    @Test func capsQualityToDisplay() {
        let ranked = StreamRanker.rank([
            stream("[RD+]", "2160p", url: "https://uhd"),
            stream("[RD+]", "1080p", url: "https://fhd"),
        ], device: DeviceCapabilities(maxQuality: .fullHD, decodesHEVC: true))
        #expect(ranked.first?.url == "https://fhd")
    }

    @Test func avoidsHEVCWhenTheDeviceCannotDecodeIt() {
        let streams = [
            stream("4K", "Movie.2160p.HEVC.mkv", url: "https://hevc4k"),
            stream("1080p", "Movie.1080p.x265.mkv", url: "https://hevc"),
            stream("1080p", "Movie.1080p.H.264.mkv", url: "https://avc"),
        ]
        let appleTVHD = DeviceCapabilities(maxQuality: .fullHD, decodesHEVC: false)
        #expect(StreamRanker.rank(streams, device: appleTVHD).map(\.url) == ["https://avc", "https://hevc", "https://hevc4k"])
        #expect(StreamRanker.rank(streams, device: .all).first?.url == "https://hevc4k")
    }

    @Test func dedupesAndPushesUnplayableLast() {
        let ranked = StreamRanker.rank([
            stream("[RD+]", "2160p", url: nil, infoHash: "h"),
            stream("A", "720p", url: "https://same"),
            stream("B", "720p", url: "https://same"),
        ])
        #expect(ranked.count == 2)
        #expect(ranked.last?.infoHash == "h")
    }

    @Test func candidatesArePlayableAndLimited() {
        let streams = (0..<5).map { stream("[RD+]", "1080p", url: "https://\($0)") } + [stream("T", url: nil, infoHash: "h")]
        let candidates = StreamRanker.playbackCandidates(streams)
        #expect(candidates.count == 3)
        #expect(candidates.allSatisfy { $0.isPlayable })
        #expect(candidates.first?.url == "https://0")
    }
}
