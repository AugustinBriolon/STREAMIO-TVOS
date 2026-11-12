import Foundation

public struct StreamsResponse: Codable {
    public let streams: [StreamItem]?
}

public enum StreamQuality: Int, Comparable, Sendable {
    case sd = 0
    case hd720 = 1
    case fullHD = 2
    case uhd = 3

    public static func < (lhs: StreamQuality, rhs: StreamQuality) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .uhd: return "4K"
        case .fullHD: return "1080p"
        case .hd720: return "720p"
        case .sd: return "SD"
        }
    }
}

public struct StreamBehaviorHints: Codable, Hashable, Sendable {
    public let bingeGroup: String?
    public let filename: String?
    public let notWebReady: Bool?
    /// Adaptive YouTube audio URL (AAC); VLC plays it via `:input-slave=`.
    public let audioURL: String?

    public init(
        bingeGroup: String? = nil,
        filename: String? = nil,
        notWebReady: Bool? = nil,
        audioURL: String? = nil
    ) {
        self.bingeGroup = bingeGroup
        self.filename = filename
        self.notWebReady = notWebReady
        self.audioURL = audioURL
    }
}

public struct StreamItem: Codable, Identifiable, Hashable, Sendable {
    public let name: String?
    public let title: String?
    public let description: String?
    public let url: String?
    public let infoHash: String?
    public let fileIdx: Int?
    public let externalUrl: String?
    public let behaviorHints: StreamBehaviorHints?

    public init(
        name: String? = nil, title: String? = nil, description: String? = nil, url: String? = nil,
        infoHash: String? = nil, fileIdx: Int? = nil, externalUrl: String? = nil,
        behaviorHints: StreamBehaviorHints? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.url = url
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.externalUrl = externalUrl
        self.behaviorHints = behaviorHints
    }

    /// Stable across renders and addons: the same source always yields the same id.
    public var id: String {
        if let url { return url }
        if let infoHash { return "\(infoHash):\(fileIdx ?? 0)" }
        if let externalUrl { return externalUrl }
        return "\(name ?? "")|\(title ?? "")|\(description ?? "")"
    }

    /// Addons put details in `title` (legacy) or `description` (current protocol).
    private var details: String { title ?? description ?? "" }
    private var searchableText: String { "\(name ?? "") \(details) \(behaviorHints?.filename ?? "")" }

    private func matches(_ pattern: String) -> Bool {
        searchableText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Playability

    /// Only direct HTTP(S) links can be opened by the player (no torrent engine).
    public var playableURL: URL? {
        guard let url, let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased()) else {
            return nil
        }
        return parsed
    }

    public var isPlayable: Bool { playableURL != nil }

    /// Built-in TMDB/YouTube trailer used when no personal addon is configured.
    public static let trailerBingeGroup = "loge.trailer"

    public var isYouTubeTrailer: Bool {
        behaviorHints?.bingeGroup == Self.trailerBingeGroup
    }

    /// True when an addon returned a diagnostic/filter notice rather than a playable stream or torrent.
    public var isNotice: Bool { !isPlayable && infoHash == nil && !isYouTubeTrailer }

    /// Trailer resolved to googlevideo URLs for in-app VLC (muxed MP4 or adaptive video+audio).
    public static func youtubeTrailer(videoKey: String, streamURL: URL, audioURL: URL? = nil) -> StreamItem {
        StreamItem(
            name: "Bande-annonce",
            title: "YouTube · \(videoKey)",
            url: streamURL.absoluteString,
            behaviorHints: StreamBehaviorHints(
                bingeGroup: trailerBingeGroup,
                filename: "\(videoKey).mp4",
                notWebReady: nil,
                audioURL: audioURL?.absoluteString
            )
        )
    }

    /// Companion AAC URL for adaptive YouTube trailers.
    public var trailerAudioURL: URL? {
        guard isYouTubeTrailer,
              let raw = behaviorHints?.audioURL,
              let parsed = URL(string: raw),
              ["http", "https"].contains(parsed.scheme?.lowercased()) else { return nil }
        return parsed
    }

    /// French reason shown when a source cannot be played on Apple TV.
    public var unplayableReason: String? {
        if isPlayable { return nil }
        if infoHash != nil { return "Torrent direct non supporté — utilisez un addon Debrid" }
        if externalUrl != nil { return "Message de l'add-on (configuration requise)" }
        return "Information de l'add-on (aucun flux vidéo)"
    }

    /// HEVC needs a hardware decoder the Apple TV HD does not have.
    public var isHEVC: Bool { matches(#"\b(HEVC|[xh]\.?265)\b"#) }

    // MARK: Badges

    public var isDebrid: Bool {
        matches(#"\[(RD|AD|PM|DL|TB|ED|OC|PKP)\+?\]|\bDebrid\b|⚡"#)
    }

    public var quality: StreamQuality {
        if matches(#"\b(4k|2160p|uhd)\b"#) { return .uhd }
        if matches(#"\b1080p\b"#) { return .fullHD }
        if matches(#"\b720p\b"#) { return .hd720 }
        return .sd
    }

    public var hdrBadge: String? {
        if matches(#"\b(DV|DoVi)\b|Dolby[ .]?Vision"#) { return "Dolby Vision" }
        if matches(#"\bHDR10\+"#) { return "HDR10+" }
        if matches(#"\bHDR(10)?\b"#) { return "HDR" }
        return nil
    }

    public var audioBadge: String? {
        if matches(#"\bAtmos\b"#) { return "Atmos" }
        if matches(#"\b(TrueHD|DTS-HD)\b"#) { return "TrueHD" }
        if matches(#"\b7\.1\b"#) { return "7.1" }
        if matches(#"\b5\.1\b"#) { return "5.1" }
        return nil
    }

    public var providerName: String {
        guard let name, !name.isEmpty else { return "Addon" }
        let firstLine = name.components(separatedBy: .newlines).first ?? name
        return firstLine
            .replacingOccurrences(of: #"\[[A-Z]{2,3}\+?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var sizeInfo: String? { firstCapture(#"([0-9]+(?:[.,][0-9]+)?\s*(?:GB|MB|GiB|MiB))"#) }

    public var seedersInfo: String? { firstCapture(#"(?:👤|👥|seeds?:?)\s*([0-9]+)"#) }

    public var parsedTitle: String {
        let lines = details.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.first ?? name ?? "Flux vidéo"
    }

    public var fullDescription: String {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstCapture(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let text = details
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
