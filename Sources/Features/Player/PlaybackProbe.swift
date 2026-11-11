import Foundation

/// Measures what a network buffer costs and what it buys: the wait before playback starts, and the
/// stalls afterwards. Fed by the engine's own callbacks, so the numbers are the engine's, not an impression.
struct PlaybackProbe: Equatable {
    /// The playback clock ticks several times a second; a longer silence while playing is a stall.
    static let stallThreshold: TimeInterval = 1

    private var openedAt: Date?
    private var lastTick: Date?
    private(set) var startup: TimeInterval?
    private(set) var stalls = 0
    private(set) var stalledTime: TimeInterval = 0

    mutating func opened(at now: Date) {
        self = PlaybackProbe()
        openedAt = now
    }

    /// The playback clock moved. Returns the stall this tick ended, if any.
    @discardableResult
    mutating func tick(at now: Date) -> TimeInterval? {
        defer { lastTick = now }
        if startup == nil, let openedAt { startup = now.timeIntervalSince(openedAt) }
        guard let lastTick else { return nil }
        let gap = now.timeIntervalSince(lastTick)
        guard gap > Self.stallThreshold else { return nil }
        stalls += 1
        stalledTime += gap
        return gap
    }

    /// A pause or a seek stops the clock on purpose: the silence that follows is not a stall.
    mutating func clockInterrupted() {
        lastTick = nil
    }
}
