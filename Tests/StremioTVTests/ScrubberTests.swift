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
    /// Samples a clockwise quarter turn on the ring, from top (0, 1) to right (1, 0).
    @Test func clockwiseRotationIsPositive() {
        var tracker = RingTracker()
        var total = 0.0
        for step in 0...9 {
            let angle = .pi / 2 - Double(step) * (.pi / 2) / 9
            total += tracker.update(x: cos(angle) * 0.9, y: sin(angle) * 0.9) ?? 0
        }
        #expect(abs(total - .pi / 2) < 0.001)
    }

    @Test func unwrapsAcrossTheSeam() {
        var tracker = RingTracker()
        _ = tracker.update(x: cos(.pi - 0.05), y: sin(.pi - 0.05))
        let delta = tracker.update(x: cos(-.pi + 0.05), y: sin(-.pi + 0.05))
        #expect(delta == nil) // inside the dead zone
        var total = delta ?? 0
        for step in 1...10 {
            let angle = -.pi + 0.05 + Double(step) * 0.05
            total += tracker.update(x: cos(angle), y: sin(angle)) ?? 0
        }
        // 0.1 + 0.5 rad counter-clockwise across the seam.
        #expect(abs(total - -0.6) < 0.0001)
    }

    @Test func arrowClicksOnOppositeEdgesAreNotARotation() {
        var tracker = RingTracker()
        _ = tracker.update(x: 1, y: 0)
        #expect(tracker.update(x: -1, y: 0) == nil)
        #expect(tracker.update(x: -1, y: 0) == nil)
    }

    @Test func smallWobbleStaysInTheDeadZone() {
        var tracker = RingTracker()
        for step in 0..<20 {
            let angle = 0.1 * sin(Double(step))
            #expect(tracker.update(x: cos(angle), y: sin(angle)) == nil)
        }
    }

    @Test func centerTouchesAreIgnoredAndResetTheGesture() {
        var tracker = RingTracker()
        _ = tracker.update(x: 0.9, y: 0)
        #expect(tracker.update(x: 0.1, y: 0.1) == nil)
        #expect(tracker.update(x: 0, y: 0.9) == nil)
    }
}
