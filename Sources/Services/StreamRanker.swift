import UIKit
import VideoToolbox

/// What this Apple TV can decode and display.
public struct DeviceCapabilities: Equatable, Sendable {
    public let maxQuality: StreamQuality
    public let decodesHEVC: Bool

    public init(maxQuality: StreamQuality, decodesHEVC: Bool) {
        self.maxQuality = maxQuality
        self.decodesHEVC = decodesHEVC
    }

    public static let all = DeviceCapabilities(maxQuality: .uhd, decodesHEVC: true)

    /// Apple TV HD: 1080p output and no HEVC hardware decoder (its A8 cannot decode HEVC in software in real time).
    @MainActor public static var current: DeviceCapabilities {
        DeviceCapabilities(
            maxQuality: UIScreen.main.nativeBounds.height >= 2160 ? .uhd : .fullHD,
            decodesHEVC: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        )
    }
}

/// Orders addon streams so the best one for this device comes first.
public enum StreamRanker {
    /// Removes duplicates (same source returned by several addons) and sorts:
    /// playable > video codec the device decodes > debrid > highest quality the display supports > higher quality above the cap.
    public static func rank(_ streams: [StreamItem], device: DeviceCapabilities = .all) -> [StreamItem] {
        var seen = Set<String>()
        let unique = streams.filter { seen.insert($0.id).inserted }
        // Stable sort: addon order breaks ties.
        return unique.enumerated().sorted { lhs, rhs in
            let left = sortKey(lhs.element, device: device)
            let right = sortKey(rhs.element, device: device)
            if left != right { return left.lexicographicallyPrecedes(right) }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Streams to try, in order, when the user presses "Lecture".
    public static func playbackCandidates(_ streams: [StreamItem], device: DeviceCapabilities = .all, limit: Int = 3) -> [StreamItem] {
        Array(rank(streams, device: device).filter(\.isPlayable).prefix(limit))
    }

    /// Lower is better for every component.
    private static func sortKey(_ stream: StreamItem, device: DeviceCapabilities) -> [Int] {
        let quality = stream.quality
        let fitsDisplay = quality <= device.maxQuality
        let decodable = device.decodesHEVC || !stream.isHEVC
        return [
            stream.isPlayable ? 0 : 1,
            decodable ? 0 : 1,
            stream.isDebrid ? 0 : 1,
            fitsDisplay ? 0 : 1,
            fitsDisplay ? -quality.rawValue : quality.rawValue,
        ]
    }
}
