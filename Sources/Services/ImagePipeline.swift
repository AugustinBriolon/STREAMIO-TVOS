import ImageIO
import UIKit

/// Loads artwork off the main thread and decodes it already reduced to the size it is displayed at.
///
/// Measured on the Apple TV HD (A8): with `AsyncImage`, browsing rows dropped 13 % of frames; decoding full
/// size posters and backdrops on first draw was a large part of it. Here the network fetch and the
/// ImageIO downsampling run in a detached task and finished images are cached in memory.
actor ImagePipeline {
    static let shared = ImagePipeline()

    // NSCache is thread-safe; `cached` reads it synchronously so already-loaded images show without a flash.
    nonisolated(unsafe) private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    nonisolated static func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)@\(Int(maxPixel))" as NSString
    }

    /// TMDB serves every image at several widths. Models carry the large one (`w500` posters, `w1280`
    /// backdrops); a card needs far less, so fetch the smallest rendition that still covers `maxPixel`
    /// (the longest displayed side): a third of the bytes to download and decode for a poster on a 1080p TV.
    nonisolated static func sizedURL(_ url: URL, maxPixel: CGFloat) -> URL {
        guard url.host == "image.tmdb.org" else { return url }
        let renditions: [(large: String, small: String, covers: CGFloat)] = [
            ("/t/p/w500/", "/t/p/w342/", 513),   // 2:3 poster: w342 is 513 px tall
            ("/t/p/w1280/", "/t/p/w780/", 780),  // 16:9 backdrop: 780 px wide
        ]
        for rendition in renditions where maxPixel <= rendition.covers && url.path.hasPrefix(rendition.large) {
            return URL(string: url.absoluteString.replacingOccurrences(of: rendition.large, with: rendition.small)) ?? url
        }
        return url
    }

    nonisolated func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: Self.key(url, maxPixel))
    }

    /// Backdrop with the page scrims baked in: one opaque layer for the compositor instead of an image
    /// plus three blended full-screen gradients redrawn under every scrolling frame.
    func backdrop(for url: URL, dimming: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)@bd\(Int(dimming * 100))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let base = await image(for: url, maxPixel: 1280) else { return nil }
        let composed = await Task.detached(priority: .userInitiated) { Self.composeBackdrop(base, dimming: dimming) }.value
        cache.setObject(composed, forKey: key, cost: Int(composed.size.width * composed.size.height * 4))
        return composed
    }

    nonisolated func cachedBackdrop(_ url: URL, dimming: CGFloat) -> UIImage? {
        cache.object(forKey: "\(url.absoluteString)@bd\(Int(dimming * 100))" as NSString)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = Self.key(url, maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        if let running = inFlight[key as String] { return await running.value }

        let source = Self.sizedURL(url, maxPixel: maxPixel)
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: source),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    /// Warms the cache in the background, `concurrency` downloads at a time, so rows are already
    /// decoded when the user scrolls to them.
    func prefetch(_ urls: [URL], maxPixel: CGFloat, concurrency: Int = 3) async {
        var iterator = urls.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            func addNext() {
                guard let url = iterator.next() else { return }
                group.addTask(priority: .utility) { _ = await self.image(for: url, maxPixel: maxPixel) }
            }
            for _ in 0..<concurrency { addNext() }
            while await group.next() != nil { addNext() }
        }
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true, // decode here, not on first draw
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Draws `image` aspect-filled on a 16:9 canvas, then the page scrims (bottom and leading gradients, optional dimming).
    nonisolated static func composeBackdrop(_ image: UIImage, dimming: CGFloat) -> UIImage {
        let size = CGSize(width: 1280, height: 720)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let canvas = UIColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            canvas.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let ratio = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))

            let space = CGColorSpaceCreateDeviceRGB()
            // Bottom: clear from the middle, canvas at the bottom.
            let bottom = CGGradient(colorsSpace: space, colors: [
                canvas.withAlphaComponent(0).cgColor, canvas.withAlphaComponent(0.7).cgColor, canvas.cgColor,
            ] as CFArray, locations: [0, 0.5, 1])!
            cg.drawLinearGradient(bottom, start: CGPoint(x: 0, y: size.height / 2), end: CGPoint(x: 0, y: size.height), options: [])

            // Leading: canvas at 90 % fading to clear at 65 % of the width.
            let leading = CGGradient(colorsSpace: space, colors: [
                canvas.withAlphaComponent(0.9).cgColor, canvas.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(leading, start: .zero, end: CGPoint(x: size.width * 0.65, y: 0), options: [])

            UIColor.black.withAlphaComponent(dimming).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
        }
    }
}
