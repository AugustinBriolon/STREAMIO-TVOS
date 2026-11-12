import Foundation
import Testing
@testable import Loge

struct YouTubeStreamResolverTests {
    @Test func picksProgressive720WhenAvailable() async throws {
        let payload: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "formats": [
                    ["itag": 18, "mimeType": "video/mp4", "url": "https://googlevideo.test/itag18.mp4"],
                    ["itag": 22, "mimeType": "video/mp4", "url": "https://googlevideo.test/itag22.mp4"],
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let session = URLSession(configuration: Self.mockConfig(data: data, status: 200))
        let resolved = await YouTubeStreamResolver(session: session).resolve(videoKey: "abc")
        #expect(resolved?.videoURL.absoluteString == "https://googlevideo.test/itag22.mp4")
        #expect(resolved?.audioURL == nil)
        #expect(resolved?.height == 720)
    }

    @Test func picksAdaptive1080WithOriginalAudioNotAutoDub() {
        let payload: [String: Any] = [
            "streamingData": [
                "formats": [
                    ["itag": 18, "height": 360, "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
                     "url": "https://googlevideo.test/itag18.mp4"],
                ],
                "adaptiveFormats": [
                    ["itag": 137, "height": 1080, "bitrate": 4_000_000,
                     "mimeType": "video/mp4; codecs=\"avc1.640028\"",
                     "url": "https://googlevideo.test/itag137.mp4"],
                    ["itag": 140, "bitrate": 130_000,
                     "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                     "url": "https://googlevideo.test/fr-dub.m4a",
                     "audioTrack": ["id": "fr-FR.10", "displayName": "Français (FR)", "audioIsDefault": true]],
                    ["itag": 140, "bitrate": 130_000,
                     "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                     "url": "https://googlevideo.test/en-original.m4a",
                     "audioTrack": ["id": "en-US.4", "displayName": "Anglais (US) original", "audioIsDefault": false]],
                ],
            ],
        ]
        let resolved = YouTubeStreamResolver.pickBestStream(from: payload, preferredLanguage: "fr")
        #expect(resolved?.videoURL.absoluteString == "https://googlevideo.test/itag137.mp4")
        #expect(resolved?.audioURL?.absoluteString == "https://googlevideo.test/en-original.m4a")
        #expect(resolved?.progressiveFallbackURL?.absoluteString == "https://googlevideo.test/itag18.mp4")
        #expect(resolved?.height == 1080)
    }

    @Test func prefersOriginalMatchingPreferredLanguage() {
        let frOriginal = YouTubeStreamResolver.MediaFormat(
            url: URL(string: "https://a/fr.m4a")!, kind: .audio, height: 0, bitrate: 100,
            isAVC: false, isAAC: true, trackID: "fr-FR.4", displayName: "Français (FR) original"
        )
        let enOriginal = YouTubeStreamResolver.MediaFormat(
            url: URL(string: "https://a/en.m4a")!, kind: .audio, height: 0, bitrate: 100,
            isAVC: false, isAAC: true, trackID: "en-US.4", displayName: "English (US) original"
        )
        #expect(YouTubeStreamResolver.audioRank(frOriginal, preferredLanguage: "fr")
            > YouTubeStreamResolver.audioRank(enOriginal, preferredLanguage: "fr"))
    }

    @Test func returnsNilWhenUnplayable() async throws {
        let payload: [String: Any] = ["playabilityStatus": ["status": "UNPLAYABLE"]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let session = URLSession(configuration: Self.mockConfig(data: data, status: 200))
        let url = await YouTubeStreamResolver(session: session).resolvePlayableURL(videoKey: "abc")
        #expect(url == nil)
    }

    @Test func youtubeTrailerStoresAudioSlave() {
        let video = URL(string: "https://googlevideo.test/v.mp4")!
        let audio = URL(string: "https://googlevideo.test/a.m4a")!
        let item = StreamItem.youtubeTrailer(videoKey: "k", streamURL: video, audioURL: audio)
        #expect(item.isYouTubeTrailer)
        #expect(item.trailerAudioURL == audio)
    }

    private static func mockConfig(data: Data, status: Int) -> URLSessionConfiguration {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://www.youtube.com/youtubei/v1/player")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
