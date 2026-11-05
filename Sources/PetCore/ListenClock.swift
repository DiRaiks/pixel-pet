import Foundation

/// Timing while the pet listens: whether it's quiet right now (the waves stop and the dots show), and when
/// listening stops by itself. Held down, it stops when let go; hands-free (⌃⌥L), after a pause once
/// something was said, or if nothing is said at all.
public struct ListenClock: Sendable {
    /// Below this level (dBFS) it counts as quiet.
    public static let quietBelow: Float = -45
    /// Quiet this long shows the dots.
    public static let quietAfter: TimeInterval = 1.5
    /// Hands-free: a pause this long after speech ends it.
    public static let pauseToStop: TimeInterval = 4
    /// Hands-free: nothing said for this long ends it.
    public static let nothingToStop: TimeInterval = 10
    /// One take, however it's started.
    public static let longest: TimeInterval = 120

    public let started: Date
    public let handsFree: Bool
    private var lastSound: Date?
    public private(set) var isQuiet = false

    public init(started: Date, handsFree: Bool) {
        self.started = started
        self.handsFree = handsFree
    }

    /// Feed the input level (dBFS); returns whether it's quiet now.
    @discardableResult
    public mutating func update(level: Float, at now: Date) -> Bool {
        if level >= Self.quietBelow { lastSound = now }
        isQuiet = now.timeIntervalSince(lastSound ?? started) >= Self.quietAfter
        return isQuiet
    }

    /// Whether listening should end by itself now.
    public func shouldStop(at now: Date) -> Bool {
        if now.timeIntervalSince(started) >= Self.longest { return true }
        guard handsFree else { return false }
        if let lastSound { return now.timeIntervalSince(lastSound) >= Self.pauseToStop }
        return now.timeIntervalSince(started) >= Self.nothingToStop
    }
}
