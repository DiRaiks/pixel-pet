import Foundation

/// Time at the Mac without a break, from the system's idle time (any keyboard or mouse input counts; what
/// you do isn't looked at). Five minutes away is a break. After `interval` of work the pet holds up a mug:
/// for 3 minutes, again 20 minutes later, or 15 minutes after a click on it, until a break comes.
public struct BreakClock: Sendable {
    public static let breakAfter: TimeInterval = 5 * 60
    public static let showFor: TimeInterval = 3 * 60
    public static let repeatAfter: TimeInterval = 20 * 60
    public static let snoozeFor: TimeInterval = 15 * 60
    /// The status card shows the count this close to the reminder.
    public static let nearBy: TimeInterval = 15 * 60
    public static let choices: [Int] = [0, 45, 60, 90]

    public enum Change: Equatable, Sendable { case show, hide, welcomeBack }

    /// Minutes of work before the reminder; 0 is off.
    public var minutes: Int
    /// When the current stretch of work began (nil while away).
    var workStart: Date?
    var hintSince: Date?
    var notBefore: Date?
    /// The stretch before this break reached the reminder: coming back earns a hop.
    var earnedBreak = false
    var away = false

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public var showing: Bool { hintSince != nil }
    var interval: TimeInterval { TimeInterval(minutes * 60) }

    /// Called every half minute or so; `userIdle` is the seconds since the last input.
    public mutating func update(now: Date, userIdle: TimeInterval) -> Change? {
        if userIdle >= Self.breakAfter {
            let wasShowing = showing
            if let start = workStart, interval > 0, now.addingTimeInterval(-userIdle).timeIntervalSince(start) >= interval {
                earnedBreak = true
            }
            workStart = nil
            hintSince = nil
            notBefore = nil
            away = true
            return wasShowing ? .hide : nil
        }
        if workStart == nil {
            workStart = now.addingTimeInterval(-userIdle)
            if away, earnedBreak {
                away = false
                earnedBreak = false
                return .welcomeBack
            }
            away = false
        }
        guard minutes > 0, let start = workStart else { return hide(until: nil) }
        if let since = hintSince {
            guard now.timeIntervalSince(since) >= Self.showFor else { return nil }
            return hide(until: now.addingTimeInterval(Self.repeatAfter))
        }
        if now.timeIntervalSince(start) >= interval, now >= notBefore ?? .distantPast {
            hintSince = now
            return .show
        }
        return nil
    }

    /// A click on the mug: later.
    public mutating func snooze(now: Date) -> Change? {
        hide(until: now.addingTimeInterval(Self.snoozeFor))
    }

    /// How long this stretch has gone, once it's within `nearBy` of the reminder (for the status card).
    public func workedNearReminder(now: Date) -> TimeInterval? {
        guard minutes > 0, let start = workStart else { return nil }
        let worked = now.timeIntervalSince(start)
        return worked >= interval - Self.nearBy ? worked : nil
    }

    private mutating func hide(until next: Date?) -> Change? {
        guard showing else { return nil }
        hintSince = nil
        notBefore = next
        return .hide
    }
}
