import Foundation
import Testing
@testable import StremioTV

struct ScrubberTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func previewThenCommit() {
        var scrubber = Scrubber()
        scrubber.step(forward: true, current: 100, duration: 1000, now: t0)
        #expect(scrubber.isActive)
        #expect(scrubber.position == 110)
        #expect(scrubber.commit() == 110)
        #expect(!scrubber.isActive)
    }

    @Test func cancelReturnsToOrigin() {
        var scrubber = Scrubber()
        scrubber.step(forward: false, current: 100, duration: 1000, now: t0)
        #expect(scrubber.position == 90)
        #expect(scrubber.cancel() == 100)
        #expect(scrubber.commit() == nil)
    }

    @Test func repeatedPressesAccelerate() {
        var scrubber = Scrubber()
        for index in 0..<6 {
            scrubber.step(forward: true, current: 0, duration: 10_000, now: t0.addingTimeInterval(Double(index) * 0.3))
        }
        // 10 + 10 + 20 + 30 + 60 + 60
        #expect(scrubber.position == 190)
        scrubber.step(forward: true, current: 0, duration: 10_000, now: t0.addingTimeInterval(10))
        #expect(scrubber.position == 200)
    }

    @Test func clampsToMediaBounds() {
        var scrubber = Scrubber()
        scrubber.step(forward: false, current: 5, duration: 100, now: t0)
        #expect(scrubber.position == 0)
        scrubber.jog(radians: 20 * .pi, current: 0, duration: 100)
        #expect(scrubber.position == 99)
    }

    @Test func oneTurnMatchesDurationScale() {
        var scrubber = Scrubber()
        scrubber.jog(radians: 2 * .pi, current: 1000, duration: 7200)
        #expect(scrubber.position == 1360)
        #expect(Scrubber.secondsPerTurn(1500) == 120)
    }
}

struct RingTrackerTests {
    /// Feeds samples and returns the total rotation reported (nil samples count as 0).
    private func total(_ samples: [(Double, Double)]) -> Double {
        var tracker = RingTracker()
        return samples.reduce(0) { $0 + (tracker.update(x: $1.0, y: $1.1) ?? 0) }
    }

    /// Clockwise arc at `radius` from `start` over `sweep` radians, 20 samples.
    private func arc(radius: Double = 0.9, start: Double = .pi / 2, sweep: Double) -> [(Double, Double)] {
        (0...20).map { step in
            let angle = start - sweep * Double(step) / 20
            return (cos(angle) * radius, sin(angle) * radius)
        }
    }

    /// Straight vertical swipe at column `x`, finger moving from `top` to `bottom`.
    private func verticalSwipe(x: Double, top: Double, bottom: Double) -> [(Double, Double)] {
        (0...20).map { step in (x, top + (bottom - top) * Double(step) / 20) }
    }

    @Test func clockwiseCircleIsPositive() {
        #expect(abs(total(arc(sweep: .pi)) - .pi) < 0.35) // loses the dead-zone share of the first samples only
        #expect(total(arc(sweep: .pi)) > 0)
    }

    @Test func counterClockwiseCircleIsNegative() {
        #expect(total(arc(sweep: -.pi)) < 0)
    }

    /// The bug: a thumb swiping down off-center follows an arc around the pad center.
    @Test(arguments: [0.6, 0.7, 0.75, 0.8, 0.9])
    func straightSwipeDownIsNotAJog(x: Double) {
        let half = (1 - x * x).squareRoot()
        #expect(total(verticalSwipe(x: x, top: half, bottom: -half)) == 0)
        #expect(total(verticalSwipe(x: -x, top: half, bottom: -half)) == 0)
    }

    @Test func straightSwipeOnASquarePadIsNotAJog() {
        #expect(total(verticalSwipe(x: 0.95, top: 0.9, bottom: -0.9)) == 0)
        #expect(total(verticalSwipe(x: 0.95, top: -0.9, bottom: 0.9)) == 0)
    }

    @Test func horizontalSwipeIsNotAJog() {
        let half = (1 - 0.7 * 0.7).squareRoot()
        let swipe = (0...20).map { step in (-half + 2 * half * Double(step) / 20, 0.7) }
        #expect(total(swipe) == 0)
    }

    @Test func unwrapsAcrossTheSeam() {
        // Counter-clockwise half turn that crosses the ±π seam (2.84 rad -> 5.98 rad).
        let samples = arc(start: .pi - 0.3, sweep: -.pi)
        #expect(total(samples) < -2.5)
    }

    @Test func arrowClicksOnOppositeEdgesAreNotARotation() {
        var tracker = RingTracker()
        _ = tracker.update(x: 1, y: 0)
        #expect(tracker.update(x: -1, y: 0) == nil)
        #expect(tracker.update(x: -1, y: 0) == nil)
    }

    @Test func centerTouchesAreIgnoredAndResetTheGesture() {
        var tracker = RingTracker()
        _ = tracker.update(x: 0.9, y: 0)
        #expect(tracker.update(x: 0.1, y: 0.1) == nil)
        #expect(tracker.update(x: 0, y: 0.9) == nil)
    }

    @Test func smallWobbleStaysInTheDeadZone() {
        var tracker = RingTracker()
        for step in 0..<20 {
            let angle = 0.1 * sin(Double(step))
            #expect(tracker.update(x: cos(angle), y: sin(angle)) == nil)
        }
    }

    @Test func gestureEndsWhenTheFingerLeavesTheRing() {
        var tracker = RingTracker()
        for sample in arc(sweep: .pi) { _ = tracker.update(x: sample.0, y: sample.1) }
        _ = tracker.update(x: 0, y: 0)            // lifted / center
        #expect(tracker.update(x: 0.9, y: 0) == nil) // new touch must re-earn the dead zone
        #expect(tracker.update(x: 0.9, y: -0.05) == nil)
    }
}
