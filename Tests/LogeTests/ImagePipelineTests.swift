import Testing
import UIKit
@testable import Loge

struct ImagePipelineTests {
    private func pngData(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .pngData { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }

    @Test func downsampleLimitsTheLongestSideAndKeepsAspect() throws {
        let image = try #require(ImagePipeline.downsample(pngData(width: 2000, height: 1000), maxPixel: 500))
        #expect(max(image.size.width, image.size.height) <= 500)
        #expect(abs(image.size.width / image.size.height - 2) < 0.02)
    }

    @Test func tmdbImagesAreFetchedAtTheSmallestSizeCoveringTheDisplay() throws {
        let poster = try #require(URL(string: "https://image.tmdb.org/t/p/w500/abc.jpg"))
        let backdrop = try #require(URL(string: "https://image.tmdb.org/t/p/w1280/abc.jpg"))
        let other = try #require(URL(string: "https://images.metahub.space/poster/medium/tt1/img"))
        #expect(ImagePipeline.sizedURL(poster, maxPixel: 330).absoluteString == "https://image.tmdb.org/t/p/w342/abc.jpg")
        #expect(ImagePipeline.sizedURL(poster, maxPixel: 660) == poster)
        #expect(ImagePipeline.sizedURL(backdrop, maxPixel: 400).absoluteString == "https://image.tmdb.org/t/p/w780/abc.jpg")
        #expect(ImagePipeline.sizedURL(backdrop, maxPixel: 1280) == backdrop)
        #expect(ImagePipeline.sizedURL(other, maxPixel: 100) == other)
    }

    @Test func downsampleRejectsNonImageData() {
        #expect(ImagePipeline.downsample(Data("not an image".utf8), maxPixel: 500) == nil)
    }

    @Test func composedBackdropIsA16by9Canvas() throws {
        let source = try #require(UIImage(data: pngData(width: 800, height: 800)))
        let composed = ImagePipeline.composeBackdrop(source, dimming: 0.3)
        #expect(composed.size == CGSize(width: 1280, height: 720))
    }

    @Test func cacheKeysSeparateSizes() {
        let url = URL(string: "https://a.io/p.jpg")!
        #expect(ImagePipeline.key(url, 330) != ImagePipeline.key(url, 660))
    }
}
