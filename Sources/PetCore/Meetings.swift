import Foundation

/// A calendar event, reduced to what the pet needs. Titles stay in memory, never written anywhere.
public struct Meeting: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    /// It has a link to a video or voice call.
    public var hasCall: Bool

    public init(title: String, start: Date, end: Date, hasCall: Bool) {
        self.title = title
        self.start = start
        self.end = end
        self.hasCall = hasCall
    }
}

/// Spots a call link in an event's URL, location or notes.
public enum MeetingLink {
    /// Host-and-path pieces that mean a call, not just any page of the same service.
    static let patterns = [
        "zoom.us/j/", "zoom.us/my/", "zoom.us/s/", "zoom.us/wc/", "zoomgov.com/j/", "zoommtg://",
        "meet.google.com/", "teams.microsoft.com/l/meetup-join", "teams.microsoft.com/meet/", "teams.live.com/meet/",
        "webex.com/meet/", "webex.com/join/", "webex.com/wbxmjs/", ".webex.com/j.php", "meet.jit.si/", "whereby.com/",
        "facetime.apple.com/join", "app.slack.com/huddle/", "bluejeans.com/", "gotomeet.me/", "gotomeeting.com/join/",
        "chime.aws/", "around.co/",
    ]

    public static func isCall(_ texts: [String?]) -> Bool {
        texts.compactMap { $0?.lowercased() }.contains { text in patterns.contains { text.contains($0) } }
    }
}

/// When the pet gets ready for a call: `soon` from 5 minutes to 1 minute before it starts, `now` from 1
/// minute before to 1 minute after; then it goes back to whatever it was doing.
public enum MeetingPlan {
    public enum Phase: Equatable, Sendable { case none, soon, now }

    public static let soonBefore: TimeInterval = 5 * 60
    public static let nowBefore: TimeInterval = 60
    public static let nowAfter: TimeInterval = 60
    /// The status card mentions a call this far ahead.
    public static let mentionWithin: TimeInterval = 60 * 60

    /// `dismissed`: start times of calls the user waved away (a click on the pet).
    public static func phase(for meetings: [Meeting], now: Date, dismissed: Set<Date> = []) -> Phase {
        var result = Phase.none
        for m in meetings where m.hasCall && !dismissed.contains(m.start) {
            let until = m.start.timeIntervalSince(now)
            if until <= nowBefore, until >= -nowAfter { return .now }
            if until <= soonBefore, until > nowBefore { result = .soon }
        }
        return result
    }

    /// The call the pet is getting ready for right now (soon or now), if any.
    public static func current(for meetings: [Meeting], now: Date, dismissed: Set<Date> = []) -> Meeting? {
        meetings.filter { m in
            let until = m.start.timeIntervalSince(now)
            return m.hasCall && !dismissed.contains(m.start) && until <= soonBefore && until >= -nowAfter
        }.min { $0.start < $1.start }
    }

    /// The next moment the phase or the status card's mention changes.
    public static func nextChange(for meetings: [Meeting], now: Date) -> Date? {
        meetings.filter(\.hasCall).flatMap { m in
            [m.start.addingTimeInterval(-mentionWithin), m.start.addingTimeInterval(-soonBefore),
             m.start.addingTimeInterval(-nowBefore), m.start.addingTimeInterval(nowAfter)]
        }.filter { $0 > now }.min()
    }

    /// The next call starting within the hour (or just started), for the status card.
    public static func upcoming(_ meetings: [Meeting], now: Date) -> Meeting? {
        meetings.filter { $0.hasCall && $0.start.timeIntervalSince(now) >= -nowAfter
            && $0.start.timeIntervalSince(now) <= mentionWithin }
            .min { $0.start < $1.start }
    }
}
