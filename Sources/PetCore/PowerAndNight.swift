import Foundation

/// The Mac's power: battery level (nil without a battery) and whether it runs on the adapter.
public struct PowerReading: Equatable, Sendable {
    public var percent: Int?
    public var onAC: Bool
    public static let lowAt = 20

    public init(percent: Int?, onAC: Bool) {
        self.percent = percent
        self.onAC = onAC
    }

    /// Low and not charging: the pet droops.
    public var isLow: Bool { !onAC && (percent.map { $0 <= Self.lowAt } ?? false) }

    /// Just plugged in (a laptop going from battery to the adapter); never at launch.
    public static func pluggedIn(from old: PowerReading?, to new: PowerReading) -> Bool {
        guard let old, new.percent != nil else { return false }
        return !old.onAC && new.onAC
    }
}

/// Late at night the desk gets a lamp, and the mug holds tea.
public enum NightDesk {
    public static let startHour = 22
    public static let endHour = 5

    public static func isLate(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= startHour || hour < endHour
    }

    /// The next 22:00 or 05:00 after `date`, to redraw the desk then.
    public static func nextChange(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        [startHour, endHour].compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0, second: 0), matchingPolicy: .nextTime)
        }.min() ?? date.addingTimeInterval(3600)
    }
}
