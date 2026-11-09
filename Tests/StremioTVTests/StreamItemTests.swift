import Foundation
import Testing
@testable import StremioTV

struct StreamItemTests {
    @Test(arguments: [
        ("[RD+] Torrentio", true),
        ("[AD] Torrentio", true),
        ("Comet ⚡", true),
        ("Real-Debrid Lumio", true),
        ("HEADSHOT ADVENTURE PMX", false),
        ("Torrentio 1080p", false),
    ])
    func detectsDebridWithoutFalsePositives(name: String, expected: Bool) {
        #expect(stream(name).isDebrid == expected)
    }

    @Test(arguments: [
        ("Movie.2160p.WEB", StreamQuality.uhd),
        ("Movie 4K HDR", .uhd),
        ("Movie.1080p.BluRay", .fullHD),
        ("Movie.720p", .hd720),
        ("Movie DVDRip", .sd),
    ])
    func parsesQuality(title: String, expected: StreamQuality) {
        #expect(stream("Addon", title).quality == expected)
    }

    @Test func dvdRipIsNotDolbyVision() {
        #expect(stream("Addon", "Movie.DVDRip.x264").hdrBadge == nil)
        #expect(stream("Addon", "Movie.2160p.DV.HDR").hdrBadge == "Dolby Vision")
        #expect(stream("Addon", "Movie.2160p.HDR10+").hdrBadge == "HDR10+")
    }

    @Test func idIsStableAndSourceBased() {
        let torrent = stream("A", url: nil, infoHash: "abc")
        #expect(torrent.id == torrent.id)
        #expect(torrent.id == "abc:0")
        #expect(stream("A").id == "https://cdn/x.mp4")
    }

    @Test func onlyHTTPLinksArePlayable() {
        #expect(stream("A").isPlayable)
        let torrent = stream("A", url: nil, infoHash: "abc")
        #expect(!torrent.isPlayable)
        #expect(torrent.unplayableReason?.contains("Debrid") == true)
        #expect(!stream("A", url: "magnet:?xt=urn").isPlayable)
    }

    @Test func readsDetailsFromDescriptionField() throws {
        let json = #"{"name":"[RD+] Torrentio","description":"Movie.1080p.mkv\n💾 2.4 GB 👤 52","url":"https://x"}"#
        let item = try JSONDecoder().decode(StreamItem.self, from: Data(json.utf8))
        #expect(item.quality == .fullHD)
        #expect(item.sizeInfo == "2.4 GB")
        #expect(item.seedersInfo == "52")
        #expect(!item.isHEVC)
        #expect(stream("A", "Movie.2160p.WEB.H265-POKE.mkv").isHEVC)
        #expect(item.providerName == "Torrentio")
        #expect(item.parsedTitle == "Movie.1080p.mkv")
    }
}
