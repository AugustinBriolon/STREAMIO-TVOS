import Testing
@testable import Loge

struct ThumbnailPlanTests {
    @Test func gridIsCappedAndStartsNearPlayback() {
        let plan = ThumbnailProvider.prefetchPlan(duration: 6518, around: 600)
        #expect(plan.count <= ThumbnailProvider.maxPrefetch)
        #expect(Set(plan).count == plan.count)
        // First frames are the ones around 10:00, where the user is.
        #expect(abs(plan[0] - ThumbnailProvider.bucket(for: 600)) <= ThumbnailProvider.bucket(for: 6518 / 40))
        #expect(plan.allSatisfy { $0 >= 0 && Double($0) * ThumbnailProvider.bucketSeconds < 6518 + 10 })
    }

    @Test func shortEpisodesUseOneFramePerMinute() {
        #expect(ThumbnailProvider.prefetchPlan(duration: 1500, around: 0).count == 25)
        #expect(ThumbnailProvider.prefetchPlan(duration: 0, around: 0).isEmpty)
    }

    @Test func nearestCachedFrame() {
        #expect(ThumbnailProvider.nearest(to: 30, in: [3, 27, 40]) == 27)
        #expect(ThumbnailProvider.nearest(to: 30, in: [Int]()) == nil)
    }
}
