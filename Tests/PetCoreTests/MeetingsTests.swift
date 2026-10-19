import Foundation
import Testing
@testable import PetCore

@Suite struct MeetingLinkTests {
    @Test func recognizesCallLinks() {
        #expect(MeetingLink.isCall(["https://lido-fi.zoom.us/j/8812345678?pwd=abc"]))
        #expect(MeetingLink.isCall([nil, "Join: https://meet.google.com/abc-defg-hij"]))
        #expect(MeetingLink.isCall(["https://teams.microsoft.com/l/meetup-join/19%3ameeting"]))
        #expect(MeetingLink.isCall(["Room 4", "https://app.slack.com/huddle/T123/C456"]))
        #expect(MeetingLink.isCall(["https://meet.jit.si/standup"]))
    }

    @Test func moreCallFormats() {
        for link in ["https://lido-fi.zoom.us/s/88123", "https://zoom.us/wc/88123/join", "https://agency.zoomgov.com/j/1",
                     "zoommtg://zoom.us/join?confno=1", "https://bluejeans.com/123", "https://gotomeet.me/team",
                     "https://global.gotomeeting.com/join/123", "https://chime.aws/123", "https://acme.webex.com/meet/jane",
                     "https://teams.microsoft.com/meet/123?p=abc"] {
            #expect(MeetingLink.isCall([link]), "\(link)")
        }
    }

    /// Links to the same services that aren't calls: a Teams channel, Webex help pages.
    @Test func lookAlikeLinksAreNotCalls() {
        #expect(!MeetingLink.isCall(["https://teams.microsoft.com/l/channel/19%3aabc/General"]))
        #expect(!MeetingLink.isCall(["https://help.webex.com/en-us/article/123"]))
    }

    @Test func ordinaryEventsAreNotCalls() {
        #expect(!MeetingLink.isCall(["Dentist", "Main street 5", nil]))
        #expect(!MeetingLink.isCall(["https://docs.google.com/document/d/1"]))
        #expect(!MeetingLink.isCall([]))
    }
}

@Suite struct MeetingPlanTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func meeting(in minutes: Double, call: Bool = true, length: Double = 30) -> Meeting {
        Meeting(title: "Sync", start: now.addingTimeInterval(minutes * 60),
                end: now.addingTimeInterval((minutes + length) * 60), hasCall: call)
    }

    @Test func phasesAroundTheStart() {
        #expect(MeetingPlan.phase(for: [meeting(in: 10)], now: now) == .none)
        #expect(MeetingPlan.phase(for: [meeting(in: 4)], now: now) == .soon)
        #expect(MeetingPlan.phase(for: [meeting(in: 0.5)], now: now) == .now)
        #expect(MeetingPlan.phase(for: [meeting(in: -0.5)], now: now) == .now, "just started")
        #expect(MeetingPlan.phase(for: [meeting(in: -3)], now: now) == .none, "under way: back to normal")
    }

    /// Exactly on the boundaries: 5:00 before is soon, 1:00 before is now, 1:00 after still now.
    @Test func boundariesAreInclusive() {
        #expect(MeetingPlan.phase(for: [meeting(in: 5)], now: now) == .soon)
        #expect(MeetingPlan.phase(for: [meeting(in: 1)], now: now) == .now)
        #expect(MeetingPlan.phase(for: [meeting(in: -1)], now: now) == .now)
        #expect(MeetingPlan.phase(for: [meeting(in: 5.01)], now: now) == .none)
    }

    /// Back to back: the one starting now wins over the next one being soon.
    @Test func backToBackCalls() {
        #expect(MeetingPlan.phase(for: [meeting(in: 4), meeting(in: -0.5)], now: now) == .now)
    }

    /// The status card mentions a call an hour ahead, so the monitor also wakes up then.
    @Test func wakesUpWhenACallComesWithinTheHour() {
        #expect(MeetingPlan.nextChange(for: [meeting(in: 90)], now: now) == now.addingTimeInterval(30 * 60))
    }

    /// A click on the pet dismisses the reminder for that one call; the next call still counts.
    @Test func dismissedCallsAreSkipped() {
        let first = meeting(in: 0.5), second = meeting(in: 30)
        #expect(MeetingPlan.current(for: [first, second], now: now) == first)
        let dismissed: Set<Date> = [first.start]
        #expect(MeetingPlan.phase(for: [first, second], now: now, dismissed: dismissed) == .none)
        #expect(MeetingPlan.phase(for: [first, second], now: now.addingTimeInterval(26 * 60), dismissed: dismissed) == .soon)
        #expect(MeetingPlan.current(for: [first], now: now, dismissed: dismissed) == nil)
        #expect(MeetingPlan.current(for: [second], now: now) == nil, "nothing to dismiss yet")
    }

    @Test func onlyCallsCount() {
        #expect(MeetingPlan.phase(for: [meeting(in: 3, call: false)], now: now) == .none)
        #expect(MeetingPlan.phase(for: [meeting(in: 3, call: false), meeting(in: 0.5)], now: now) == .now)
    }

    /// The monitor wakes up at the next boundary: 5 minutes before, 1 minute before, 1 minute after.
    @Test func nextChangeIsTheNearestBoundary() {
        #expect(MeetingPlan.nextChange(for: [meeting(in: 10)], now: now) == now.addingTimeInterval(5 * 60))
        #expect(MeetingPlan.nextChange(for: [meeting(in: 4)], now: now) == now.addingTimeInterval(3 * 60))
        #expect(MeetingPlan.nextChange(for: [meeting(in: 0.5)], now: now) == now.addingTimeInterval(1.5 * 60))
        #expect(MeetingPlan.nextChange(for: [meeting(in: -5)], now: now) == nil)
        #expect(MeetingPlan.nextChange(for: [], now: now) == nil)
    }

    @Test func upcomingIsTheNextCallWithinTheHour() {
        let soonest = MeetingPlan.upcoming([meeting(in: 40), meeting(in: 12), meeting(in: 5, call: false)], now: now)
        #expect(soonest?.start == now.addingTimeInterval(12 * 60))
        #expect(MeetingPlan.upcoming([meeting(in: 90)], now: now) == nil)
        #expect(MeetingPlan.upcoming([meeting(in: -0.5)], now: now)?.start == now.addingTimeInterval(-30), "starting right now")
    }
}
