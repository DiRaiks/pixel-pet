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

/// Late at night the desk gets a light (a lamp, or now and then a candle), and the mug holds tea.
public enum NightDesk {
    public static let startHour = 22
    public static let endHour = 5

    public static func isLate(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= startHour || hour < endHour
    }

    /// What lights the desk: a lamp most nights, a candle that burns down now and then.
    public enum Light: Equatable, Sendable { case lamp, candle }

    /// One light for the whole night, picked from its date (the evening it began): a candle every third
    /// night, so it stays a surprise but never flips in the middle of one.
    public static func light(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Light {
        let hour = calendar.component(.hour, from: date)
        let evening = hour < endHour ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let day = calendar.ordinality(of: .day, in: .era, for: evening) ?? 0
        return day % 3 == 0 ? .candle : .lamp
    }

    /// How far the candle has burned down, 0...3: fresh until midnight, a stub from 4:00.
    public static func candleMelt(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let since = (calendar.component(.hour, from: date) - startHour + 24) % 24
        return min(3, since / 2)
    }

    /// When the desk next looks different: every hour through the night (the candle burns down), else
    /// the next 22:00.
    public static func nextRedraw(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        guard isLate(at: date, calendar: calendar) else { return nextChange(after: date, calendar: calendar) }
        return calendar.nextDate(after: date, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(3600)
    }

    /// The next 22:00 or 05:00 after `date`, to redraw the desk then.
    public static func nextChange(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        [startHour, endHour].compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0, second: 0), matchingPolicy: .nextTime)
        }.min() ?? date.addingTimeInterval(3600)
    }
}
