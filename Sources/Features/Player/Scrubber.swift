import Foundation

/// Netflix-style seeking: moving the head only previews a position; `commit` seeks, `cancel` goes back.
/// Repeated presses accelerate (10 → 20 → 30 → 60 s per press).
struct Scrubber: Equatable {
    private(set) var origin: Double?
    private(set) var position: Double = 0
    private var lastStepAt: Date?
    private var streak = 0

    static let steps: [Double] = [10, 10, 20, 30, 60]
    /// Presses closer than this keep accelerating.
    static let streakWindow: TimeInterval = 0.6

    var isActive: Bool { origin != nil }

    /// Arrow press. `current` is the playback time, used when scrubbing starts.
    mutating func step(forward: Bool, current: Double, duration: Double, now: Date = Date()) {
        begin(at: current)
        if let lastStepAt, now.timeIntervalSince(lastStepAt) <= Self.streakWindow {
            streak = min(streak + 1, Self.steps.count - 1)
        } else {
            streak = 0
        }
        lastStepAt = now
        move(by: (forward ? 1 : -1) * Self.steps[streak], duration: duration)
    }

    /// Circular gesture on the clickpad ring: clockwise is forward. One turn covers `secondsPerTurn(duration)`.
    mutating func jog(radians: Double, current: Double, duration: Double) {
        begin(at: current)
        move(by: radians / (2 * .pi) * Self.secondsPerTurn(duration), duration: duration)
    }

    /// A 2 h film moves 6 min per turn; short episodes never less than 2 min per turn.
    static func secondsPerTurn(_ duration: Double) -> Double { max(120, duration / 20) }

    /// Ends scrubbing and returns the time to seek to.
    mutating func commit() -> Double? {
        defer { reset() }
        return isActive ? position : nil
    }

    /// Ends scrubbing and returns the time playback was at when scrubbing began.
    mutating func cancel() -> Double? {
        defer { reset() }
        return origin
    }

    private mutating func begin(at current: Double) {
        guard origin == nil else { return }
        origin = current
        position = current
    }

    private mutating func move(by seconds: Double, duration: Double) {
        let upperBound = duration > 0 ? max(duration - 1, 0) : .greatestFiniteMagnitude
        position = min(max(position + seconds, 0), upperBound)
    }

    private mutating func reset() {
        origin = nil
        lastStepAt = nil
        streak = 0
    }
}

/// Turns raw Siri Remote clickpad touches (absolute x/y in -1...1) into rotation around the ring.
/// A rotation only starts after a dead zone, so resting a thumb on the edge or clicking the arrows
/// (which also touch the ring) never jogs; an angle jump between two samples is a new touch, not motion.
struct RingTracker {
    /// Touches closer to the center than this are swipes/clicks, not ring rotation.
    static let ringRadius = 0.55
    /// Continuous motion between two samples (reported at ~60 Hz) never exceeds this.
    static let maxStep = 0.8
    /// Rotation needed before a gesture counts as a jog (~17°).
    static let deadZone = 0.3

    private var lastAngle: Double?
    private var pending = 0.0
    private var engaged = false

    /// Returns the clockwise rotation (radians) to apply for this sample, or nil.
    mutating func update(x: Double, y: Double) -> Double? {
        guard (x * x + y * y).squareRoot() >= Self.ringRadius else {
            reset()
            return nil
        }
        let angle = atan2(y, x)
        defer { lastAngle = angle }
        guard let lastAngle else { return nil }
        var delta = angle - lastAngle
        // Unwrap across the ±π seam.
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        guard abs(delta) <= Self.maxStep else {
            pending = 0
            engaged = false
            return nil
        }
        // atan2 grows counter-clockwise (y up); clockwise must be positive.
        let clockwise = -delta
        if engaged { return clockwise }
        pending += clockwise
        guard abs(pending) >= Self.deadZone else { return nil }
        engaged = true
        defer { pending = 0 }
        return pending
    }

    mutating func reset() {
        lastAngle = nil
        pending = 0
        engaged = false
    }
}
