import CoreGraphics
import Observation
import TVVLCKit

/// Scrub previews extracted from the stream itself: addons provide no trickplay (BIF) images, and each
/// frame costs 2–9 s on an Apple TV HD (open + seek into a remote MKV, measured on device).
/// So, like a trickplay track, a coarse grid is generated in the background during playback, one frame
/// at a time, and scrubbing shows the nearest cached frame immediately while the exact one is fetched.
@MainActor
@Observable
final class ThumbnailProvider: NSObject {
    private(set) var image: CGImage?

    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var duration: Double = 0
    @ObservationIgnored private var cache: [Int: CGImage] = [:]
    @ObservationIgnored private var thumbnailer: VLCMediaThumbnailer?
    @ObservationIgnored private var inFlightBucket: Int?
    @ObservationIgnored private var wantedBucket: Int?
    @ObservationIgnored private var prefetchQueue: [Int] = []
    @ObservationIgnored private var debounce: Task<Void, Never>?

    nonisolated static let bucketSeconds = 10.0
    /// Background grid: one frame per this many seconds, at most `maxPrefetch` frames.
    nonisolated static let maxPrefetch = 40

    nonisolated static func bucket(for time: Double) -> Int { Int((time / bucketSeconds).rounded()) }

    /// Grid buckets ordered outward from the playback position, where scrubbing usually starts.
    nonisolated static func prefetchPlan(duration: Double, around time: Double) -> [Int] {
        guard duration > 0 else { return [] }
        let spacing = max(60, duration / Double(maxPrefetch))
        let grid = Set(stride(from: spacing / 2, to: duration, by: spacing).map(bucket(for:)))
        let origin = bucket(for: time)
        return grid.sorted { abs($0 - origin) < abs($1 - origin) || (abs($0 - origin) == abs($1 - origin) && $0 > $1) }
    }

    /// Nearest cached bucket to `bucket`, if any.
    nonisolated static func nearest(to bucket: Int, in cached: some Collection<Int>) -> Int? {
        cached.min { abs($0 - bucket) < abs($1 - bucket) }
    }

    func reset(url: URL?) {
        self.url = url
        cache = [:]
        image = nil
        wantedBucket = nil
        prefetchQueue = []
    }

    func startPrefetch(duration: Double, around time: Double) {
        guard prefetchQueue.isEmpty, cache.isEmpty else { return }
        self.duration = duration
        prefetchQueue = Self.prefetchPlan(duration: duration, around: time)
        fetchNext()
    }

    func request(time: Double, duration: Double) {
        self.duration = duration
        let bucket = Self.bucket(for: time)
        wantedBucket = bucket
        if let nearest = Self.nearest(to: bucket, in: cache.keys) { image = cache[nearest] }
        guard cache[bucket] == nil else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.fetchNext()
        }
    }

    /// Scrub requests win over the background grid; one frame is decoded at a time.
    private func fetchNext() {
        guard inFlightBucket == nil, let url, duration > 0 else { return }
        prefetchQueue.removeAll { cache[$0] != nil }
        let bucket: Int
        if let wanted = wantedBucket, cache[wanted] == nil {
            bucket = wanted
        } else if !prefetchQueue.isEmpty {
            bucket = prefetchQueue.removeFirst()
        } else {
            return
        }
        inFlightBucket = bucket
        let media = VLCMedia(url: url)
        // Previews must show the picture only, and decoding audio would waste A8 CPU during playback.
        media.addOption(":no-spu")
        media.addOption(":no-audio")
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.thumbnailWidth = 384
        thumbnailer.thumbnailHeight = 216
        thumbnailer.snapshotPosition = Float(min(max(Double(bucket) * Self.bucketSeconds / duration, 0), 1))
        self.thumbnailer = thumbnailer
        thumbnailer.fetchThumbnail()
    }

    fileprivate func finish(_ thumbnail: CGImage?) {
        guard let bucket = inFlightBucket else { return }
        inFlightBucket = nil
        thumbnailer = nil
        if let thumbnail {
            cache[bucket] = thumbnail
            if let wanted = wantedBucket, Self.nearest(to: wanted, in: cache.keys) == bucket { image = thumbnail }
        }
        fetchNext()
    }
}

extension ThumbnailProvider: VLCMediaThumbnailerDelegate {
    nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        Task { @MainActor in self.finish(thumbnail) }
    }
}

