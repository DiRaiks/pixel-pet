import Foundation
@testable import PetCore
import Testing

struct BreakClockTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    /// Busy at the Mac: input every few seconds.
    func work(_ c: inout BreakClock, from: Double, to: Double) -> [BreakClock.Change] {
        stride(from: from, through: to, by: 0.5).compactMap { c.update(now: at($0), userIdle: 2) }
    }

    @Test func remindsAfterTheIntervalThenHidesAndRepeats() {
        var c = BreakClock(minutes: 60)
        #expect(work(&c, from: 0, to: 59.5).isEmpty)
        #expect(c.update(now: at(60), userIdle: 2) == .show)
        #expect(c.showing)
        // Shown for 3 minutes, then away; back 20 minutes later.
        #expect(work(&c, from: 60.5, to: 63) == [.hide])
        #expect(work(&c, from: 63.5, to: 82.5).isEmpty)
        #expect(c.update(now: at(83), userIdle: 2) == .show)
    }

    @Test func aClickSnoozesFifteenMinutes() {
        var c = BreakClock(minutes: 45)
        _ = work(&c, from: 0, to: 45)
        #expect(c.showing)
        #expect(c.snooze(now: at(45.5)) == .hide)
        #expect(work(&c, from: 46, to: 60).isEmpty)
        #expect(c.update(now: at(60.5), userIdle: 2) == .show)
    }

    @Test func shortPausesDontCountFiveMinutesAwayDoes() {
        var c = BreakClock(minutes: 60)
        _ = work(&c, from: 0, to: 40)
        // Three minutes reading: no input, but not a break.
        #expect(c.update(now: at(43), userIdle: 180) == nil)
        _ = work(&c, from: 43.5, to: 55)
        // Counted from the first input, two seconds before the first look.
        #expect(abs((c.workedNearReminder(now: at(55)) ?? 0) - (55 * 60 + 2)) < 0.001)
        // Six minutes away: the count starts over, and the next hour is a new one.
        #expect(c.update(now: at(61), userIdle: 360) == nil)
        #expect(work(&c, from: 61.5, to: 121).isEmpty)
        #expect(c.update(now: at(121.5), userIdle: 2) == .show)
    }

    @Test func comingBackFromAnEarnedBreakGetsAHop() {
        var c = BreakClock(minutes: 45)
        _ = work(&c, from: 0, to: 46)
        #expect(c.update(now: at(52), userIdle: 330) == .hide)
        #expect(c.update(now: at(60), userIdle: 1) == .welcomeBack)
        // A break after only a little work: no hop.
        _ = work(&c, from: 60.5, to: 70)
        #expect(c.update(now: at(80), userIdle: 400) == nil)
        #expect(c.update(now: at(81), userIdle: 1) == nil)
    }

    /// The Mac slept through lunch: no checks for an hour, and the idle time after waking may be small.
    @Test func aLongGapBetweenLooksIsABreak() {
        var c = BreakClock(minutes: 60)
        _ = work(&c, from: 0, to: 50)
        #expect(c.update(now: at(110), userIdle: 1) == nil)
        // The count started again at the wake-up: no mug for another hour.
        #expect(work(&c, from: 110.5, to: 169).isEmpty)
        #expect(c.update(now: at(170.5), userIdle: 2) == .show)
    }

    /// Asleep with the mug up, after a full hour: on waking it goes, and the earned break gets its hop.
    @Test func wakingWithTheMugUp() {
        var c = BreakClock(minutes: 45)
        _ = work(&c, from: 0, to: 46)
        #expect(c.showing)
        #expect(c.update(now: at(120), userIdle: 1) == .welcomeBack)
        #expect(!c.showing)
    }

    @Test func offMeansNothing() {
        var c = BreakClock(minutes: 0)
        #expect(work(&c, from: 0, to: 200).isEmpty)
        #expect(c.workedNearReminder(now: at(200)) == nil)
        // Turned off while showing: hides on the next look.
        var on = BreakClock(minutes: 45)
        _ = work(&on, from: 0, to: 45)
        on.minutes = 0
        #expect(on.update(now: at(45.5), userIdle: 2) == .hide)
    }

    @Test func notNearYetShowsNoCount() {
        var c = BreakClock(minutes: 60)
        _ = work(&c, from: 0, to: 30)
        #expect(c.workedNearReminder(now: at(30)) == nil)
    }
}
