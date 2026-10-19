import Foundation

/// Decides when the limits probe (one tiny `claude -p` call) may run, so it never spends quota in a loop.
public struct ProbePolicy: Sendable {
    public enum Reason: Sendable {
        /// App start: only if the remembered limits are stale.
        case launch
        /// Agents are working: at most every `busyInterval`.
        case busy
        /// The status card opened: only if the shown limits are stale.
        case panel
        /// The refresh button: always, apart from the short cooldown and failure backoff.
        case manual
    }

    public static let freshFor: TimeInterval = 10 * 60
    public static let busyInterval: TimeInterval = 30 * 60
    public static let manualCooldown: TimeInterval = 60
    static let backoff: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60]

    public private(set) var inFlight = false
    public private(set) var lastStartedAt: Date?
    public private(set) var failures = 0
    /// No probe of any kind before this moment (cooldown after success, backoff after failures).
    public private(set) var nextAllowed: Date?

    public init() {}

    public func allows(_ reason: Reason, now: Date, limitsObservedAt: Date?) -> Bool {
        guard !inFlight else { return false }
        if let nextAllowed, now < nextAllowed { return false }
        let age = limitsObservedAt.map { now.timeIntervalSince($0) } ?? .infinity
        switch reason {
        case .manual:
            return true
        case .launch, .panel:
            return age > Self.freshFor
        case .busy:
            let sinceLast = lastStartedAt.map { now.timeIntervalSince($0) } ?? .infinity
            return age > Self.busyInterval && sinceLast > Self.busyInterval
        }
    }

    public mutating func started(at now: Date) {
        inFlight = true
        lastStartedAt = now
    }

    public mutating func finished(success: Bool) {
        inFlight = false
        let start = lastStartedAt ?? Date()
        if success {
            failures = 0
            nextAllowed = start.addingTimeInterval(Self.manualCooldown)
        } else {
            failures += 1
            nextAllowed = start.addingTimeInterval(Self.backoff[min(failures, Self.backoff.count) - 1])
        }
    }
}
