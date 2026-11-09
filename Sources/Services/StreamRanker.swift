import Foundation

/// Orders addon streams so the best one for this device comes first.
public enum StreamRanker {
    /// Removes duplicates (same source returned by several addons) and sorts:
    /// playable > debrid > highest quality the display supports > non-Matroska > higher quality above the cap.
    public static func rank(_ streams: [StreamItem], maxQuality: StreamQuality = .uhd) -> [StreamItem] {
        var seen = Set<String>()
        let unique = streams.filter { seen.insert($0.id).inserted }
        // Stable sort: addon order breaks ties.
        return unique.enumerated().sorted { lhs, rhs in
            let left = sortKey(lhs.element, maxQuality: maxQuality)
            let right = sortKey(rhs.element, maxQuality: maxQuality)
            if left != right { return left.lexicographicallyPrecedes(right) }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Streams to try, in order, when the user presses "Lecture".
    public static func playbackCandidates(_ streams: [StreamItem], maxQuality: StreamQuality = .uhd, limit: Int = 3) -> [StreamItem] {
        Array(rank(streams, maxQuality: maxQuality).filter(\.isPlayable).prefix(limit))
    }

    /// Lower is better for every component.
    private static func sortKey(_ stream: StreamItem, maxQuality: StreamQuality) -> [Int] {
        let quality = stream.quality
        let fitsDisplay = quality <= maxQuality
        return [
            stream.isPlayable ? 0 : 1,
            stream.isDebrid ? 0 : 1,
            fitsDisplay ? 0 : 1,
            fitsDisplay ? -quality.rawValue : quality.rawValue,
            stream.isMatroska ? 1 : 0,
        ]
    }
}
