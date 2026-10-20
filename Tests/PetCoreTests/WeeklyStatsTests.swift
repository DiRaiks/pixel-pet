import Foundation
@testable import PetCore
import Testing

struct WeeklyStatsTests {
    var cal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }
    /// 2026-10-12 is a Monday.
    func date(_ day: Int, _ hour: Int = 12, month: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func weeksStartOnMonday() {
        let week = AgentStats.Week.containing(date(15), cal)
        #expect(week.start == date(12, 0))
        #expect(week.days.count == 7)
        // Sunday night still belongs to the same week; Monday 00:00 starts the next.
        #expect(AgentStats.Week.containing(date(18, 23), cal).start == date(12, 0))
        #expect(AgentStats.Week.containing(date(19, 0), cal).start == date(19, 0))
    }

    @Test func summaryAddsUpTheWeek() {
        var s = AgentStats()
        s.recordTurn(project: "pixel-pet", agent: .claude, active: 3600, steps: 40, at: date(12))
        s.recordTurn(project: "pixel-pet", agent: .claude, active: 1800, steps: 10, at: date(13))
        s.recordTurn(project: "api", agent: .codex, active: 600, steps: 0, at: date(13))
        for name in ["a", "b", "c"] { s.recordTurn(project: name, agent: .claude, active: 60, steps: 1, at: date(14)) }
        s.recordWait(30, at: date(13))
        s.recordWait(90, at: date(14))
        s.recordAnswerInPet(at: date(14))
        // Next week's turn doesn't count.
        s.recordTurn(project: "pixel-pet", agent: .claude, active: 999, steps: 1, at: date(19))
        let w = s.summary(of: .containing(date(15), cal), calendar: cal)
        #expect(w.total == 3600 + 1800 + 600 + 180)
        #expect(w.perDay[0].claude == 3600)
        #expect(w.perDay[1].codex == 600)
        #expect(w.turns == 6)
        #expect(w.steps == 53)
        #expect(w.projects.map(\.name) == ["pixel-pet", "api", "a"])
        #expect(w.others?.count == 2)
        #expect(w.others?.seconds == 120)
        #expect(w.longest?.seconds == 3600)
        #expect(w.longest?.weekday == 0)
        #expect(w.waits == 2 && w.waited == 120)
        #expect(w.answeredInPet == 1)
        #expect(w.worthShowing)
        #expect(w.change == nil)
    }

    @Test func weekOverWeek() {
        var s = AgentStats()
        s.recordTurn(project: "p", agent: .claude, active: 1000, steps: 1, at: date(6))
        s.recordTurn(project: "p", agent: .claude, active: 1200, steps: 1, at: date(13))
        let change = s.summary(of: .containing(date(13), cal), calendar: cal).change
        #expect(abs((change ?? 0) - 0.2) < 0.0001)
    }

    @Test func limitPeakAndHitsCountEachWindowOnce() {
        var s = AgentStats()
        let window = { (used: Double, resets: Int) in LimitWindow(usedPercent: used, resetsAt: self.date(13, resets)) }
        s.recordLimit(window(80, 15), at: date(13, 11))
        s.recordLimit(window(100, 15), at: date(13, 12))
        s.recordLimit(window(100, 15), at: date(13, 13))
        s.recordLimit(window(100, 20), at: date(13, 16))
        let w = s.summary(of: .containing(date(13), cal), calendar: cal)
        #expect(w.limitPeak == 100)
        #expect(w.limitHits == 2)
    }

    @Test func oldWeeksAreDropped() {
        var s = AgentStats()
        s.recordTurn(project: "p", agent: .claude, active: 1, steps: 0, at: date(1, month: 8))
        s.recordTurn(project: "p", agent: .claude, active: 1, steps: 0, at: date(13))
        s.prune(now: date(15), calendar: cal)
        #expect(s.days.count == 1)
    }

    @Test func newspaperOnceAWeekFromMondayMorning() {
        var s = AgentStats()
        s.recordTurn(project: "p", agent: .claude, active: 600, steps: 1, at: date(13))
        #expect(!RecapPlan.due(now: date(19, 9), shownFor: nil, stats: s, calendar: cal))  // one day only
        s.recordTurn(project: "p", agent: .claude, active: 600, steps: 1, at: date(15))
        #expect(!RecapPlan.due(now: date(19, 5), shownFor: nil, stats: s, calendar: cal))  // before 6:00
        #expect(RecapPlan.due(now: date(19, 9), shownFor: nil, stats: s, calendar: cal))
        #expect(RecapPlan.due(now: date(21, 9), shownFor: "2026-10-12", stats: s, calendar: cal))  // later that week
        #expect(!RecapPlan.due(now: date(21, 9), shownFor: "2026-10-19", stats: s, calendar: cal))
    }

    @Test func theNewspaperOpensOnceThenReadsOnALoop() {
        #expect(!PetState.newspaperOpen.loops)
        #expect(PetState.newspaper.loops)
        #expect(MotionPolicy.stillFrame(for: .newspaper) == 0)
    }

    /// A finished turn leaves its active work (waits for the user left out) and its steps.
    @Test func turnsLeaveTheirWork() {
        var r = SessionRegistry()
        let t0 = date(13, 10)
        func ev(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(sessionID: "s", cwd: "/w/p", kind: kind) }
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .toolStarted(name: "Bash", useID: "t"),
                           step: AgentStep(action: .run, object: "ls")), at: t0.addingTimeInterval(10))
        r.apply(ev(.permissionRequested), at: t0.addingTimeInterval(20))
        r.apply(ev(.toolFinished(name: "Bash", useID: "t")), at: t0.addingTimeInterval(80))
        r.apply(ev(.stopped), at: t0.addingTimeInterval(100))
        #expect(r.sessions["s"]?.lastWork == 40)
        #expect(r.sessions["s"]?.lastSteps == 1)
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = AgentStats()
        s.recordTurn(project: "p", agent: .codex, active: 5, steps: 2, at: date(13))
        try StatsStore(url: url).save(s)
        #expect(StatsStore(url: url).load() == s)
        try Data("garbage".utf8).write(to: url)
        #expect(StatsStore(url: url).load().isEmpty)
    }
}
