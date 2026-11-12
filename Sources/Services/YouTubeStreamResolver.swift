import Foundation

/// Progressive MP4 or adaptive video+audio pair that VLC can open in-process.
struct ResolvedYouTubeStream: Equatable, Sendable {
    let videoURL: URL
    /// Set when video is video-only (DASH-style); play via VLC `:input-slave=`.
    let audioURL: URL?
    let height: Int
    /// Muxed progressive fallback when adaptive + input-slave fails on device.
    let progressiveFallbackURL: URL?
}

/// Resolves a YouTube video id to the best media URLs VLC can play.
/// Prefers an Android InnerTube client that still returns direct adaptive googlevideo URLs.
struct YouTubeStreamResolver: Sendable {
    private let session: URLSession

    /// 20.10.38 still embeds adaptive URLs; 21.x often only leaves progressive 360p.
    private static let clients: [(version: String, sdk: Int)] = [
        ("20.10.38", 30),
        ("21.26.364", 30),
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolvePlayableURL(videoKey: String, preferredLanguage: String = "fr") async -> URL? {
        await resolve(videoKey: videoKey, preferredLanguage: preferredLanguage)?.videoURL
    }

    func resolve(videoKey: String, preferredLanguage: String = "fr") async -> ResolvedYouTubeStream? {
        let trimmed = videoKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lang = String(preferredLanguage.prefix(2)).lowercased()

        var best: ResolvedYouTubeStream?
        for client in Self.clients {
            guard let payload = await fetchPlayer(videoKey: trimmed, version: client.version, sdk: client.sdk, language: lang),
                  let candidate = Self.pickBestStream(from: payload, preferredLanguage: lang) else { continue }
            if best == nil || candidate.height > best!.height {
                best = candidate
            }
            if candidate.height >= 720 {
                break
            }
        }
        return best
    }

    private func fetchPlayer(videoKey: String, version: String, sdk: Int, language: String) async -> [String: Any]? {
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            return nil
        }
        let ua = "com.google.android.youtube/\(version) (Linux; U; Android 11) gzip"
        let gl = language == "en" ? "US" : language.uppercased()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("3", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.timeoutInterval = 12

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": version,
                    "androidSdkVersion": sdk,
                    "hl": language,
                    "gl": gl,
                    "userAgent": ua,
                ]
            ],
            "videoId": videoKey,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ],
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let status = (payload["playabilityStatus"] as? [String: Any])?["status"] as? String
        guard status == "OK" || status == nil else { return nil }
        return payload
    }

    /// Progressive muxed ≥720p if present; else highest AVC video + language-aware AAC; else any progressive.
    /// Skips HLS — YouTube HLS is unreliable in libVLC on tvOS.
    static func pickBestStream(from payload: [String: Any], preferredLanguage: String = "fr") -> ResolvedYouTubeStream? {
        let streaming = payload["streamingData"] as? [String: Any] ?? [:]
        let formats = (streaming["formats"] as? [[String: Any]]) ?? []
        let adaptive = (streaming["adaptiveFormats"] as? [[String: Any]]) ?? []
        let lang = String(preferredLanguage.prefix(2)).lowercased()

        let progressive = formats.compactMap(parsedProgressive(from:)).sorted { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            return lhs.bitrate > rhs.bitrate
        }
        let progressiveFallback = progressive.first?.url

        if let bestMuxed = progressive.first, bestMuxed.height >= 720 {
            return ResolvedYouTubeStream(
                videoURL: bestMuxed.url,
                audioURL: nil,
                height: bestMuxed.height,
                progressiveFallbackURL: nil
            )
        }

        let videos = adaptive.compactMap(parsedAdaptive(from:))
            .filter { $0.kind == .video && $0.isAVC }
            .sorted { lhs, rhs in
                if lhs.height != rhs.height { return lhs.height > rhs.height }
                return lhs.bitrate > rhs.bitrate
            }
        let audios = adaptive.compactMap(parsedAdaptive(from:))
            .filter { $0.kind == .audio && $0.isAAC }
            .sorted { lhs, rhs in
                let left = audioRank(lhs, preferredLanguage: lang)
                let right = audioRank(rhs, preferredLanguage: lang)
                if left != right { return left > right }
                return lhs.bitrate > rhs.bitrate
            }

        if let video = videos.first, let audio = audios.first {
            return ResolvedYouTubeStream(
                videoURL: video.url,
                audioURL: audio.url,
                height: video.height,
                progressiveFallbackURL: progressiveFallback
            )
        }
        if let muxed = progressive.first {
            return ResolvedYouTubeStream(
                videoURL: muxed.url,
                audioURL: nil,
                height: muxed.height,
                progressiveFallbackURL: nil
            )
        }
        if let video = videos.first {
            return ResolvedYouTubeStream(
                videoURL: video.url,
                audioURL: nil,
                height: video.height,
                progressiveFallbackURL: progressiveFallback
            )
        }
        return nil
    }

    /// Prefer real original audio over YouTube auto-dub defaults (`hl` often marks dub as default).
    static func audioRank(_ format: MediaFormat, preferredLanguage: String) -> Int {
        let id = format.trackID.lowercased()
        let name = format.displayName.lowercased()
        let isOriginal = name.contains("original")
        let langMatch = id == preferredLanguage
            || id.hasPrefix("\(preferredLanguage)-")
            || id.hasPrefix("\(preferredLanguage).")
        if isOriginal && langMatch { return 500 }
        if isOriginal { return 400 }
        if format.trackID.isEmpty && format.displayName.isEmpty { return 300 }
        if langMatch { return 100 } // likely auto-dub of preferred language
        return 0
    }

    enum MediaKind { case video, audio }

    struct MediaFormat {
        let url: URL
        let kind: MediaKind
        let height: Int
        let bitrate: Int
        let isAVC: Bool
        let isAAC: Bool
        let trackID: String
        let displayName: String
    }

    private struct ProgressiveFormat {
        let url: URL
        let height: Int
        let bitrate: Int
    }

    private static func parsedProgressive(from raw: [String: Any]) -> ProgressiveFormat? {
        guard let urlString = raw["url"] as? String, let url = URL(string: urlString) else { return nil }
        let mime = (raw["mimeType"] as? String ?? "").lowercased()
        guard mime.hasPrefix("video/mp4") || mime.isEmpty else { return nil }
        let height = resolvedHeight(raw: raw)
        let bitrate = raw["bitrate"] as? Int ?? raw["averageBitrate"] as? Int ?? 0
        return ProgressiveFormat(url: url, height: height, bitrate: bitrate)
    }

    private static func parsedAdaptive(from raw: [String: Any]) -> MediaFormat? {
        guard let urlString = raw["url"] as? String, let url = URL(string: urlString) else { return nil }
        let mime = (raw["mimeType"] as? String ?? "").lowercased()
        let height = resolvedHeight(raw: raw)
        let bitrate = raw["bitrate"] as? Int ?? raw["averageBitrate"] as? Int ?? 0
        let isAVC = mime.contains("avc1") || mime.contains("avc")
        let isAAC = mime.contains("mp4a") || mime.contains("aac")
        let track = raw["audioTrack"] as? [String: Any]
        let trackID = track?["id"] as? String ?? ""
        let displayName = track?["displayName"] as? String ?? ""
        if mime.hasPrefix("audio/") {
            return MediaFormat(
                url: url, kind: .audio, height: 0, bitrate: bitrate,
                isAVC: false, isAAC: isAAC || mime.contains("mp4"),
                trackID: trackID, displayName: displayName
            )
        }
        if mime.hasPrefix("video/") {
            return MediaFormat(
                url: url, kind: .video, height: height, bitrate: bitrate,
                isAVC: isAVC || mime.contains("mp4"), isAAC: false,
                trackID: "", displayName: ""
            )
        }
        return nil
    }

    private static func resolvedHeight(raw: [String: Any]) -> Int {
        if let height = raw["height"] as? Int, height > 0 { return height }
        switch raw["itag"] as? Int {
        case 37, 299, 137: return 1080
        case 22, 298, 136: return 720
        case 135: return 480
        case 18, 134: return 360
        case 133: return 240
        default: return 0
        }
    }
}
