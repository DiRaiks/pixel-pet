import Foundation
import Testing
@testable import PetCore

@Suite struct WaitReasonTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func ev(_ kind: AgentEvent.Kind, _ id: String = "s") -> AgentEvent { AgentEvent(sessionID: id, cwd: nil, kind: kind) }

    @Test func permissionPromptsAlertQuestionsAsk() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.permissionRequested), at: t0)
        #expect(r.ordered[0].waitingFor == .permission)
        #expect(PetBrain.baseState(for: r.ordered, now: t0) == .alert)

        var q = SessionRegistry()
        q.apply(ev(.promptSubmitted), at: t0)
        q.apply(ev(.toolStarted(name: "AskUserQuestion", useID: "u")), at: t0)
        #expect(q.ordered[0].waitingFor == .question)
        #expect(PetBrain.baseState(for: q.ordered, now: t0) == .question)
    }

    @Test func turnEndQuestionAndElicitationAreQuestions() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.questionAsked), at: t0)
        r.apply(ev(.stopped), at: t0)
        #expect(r.ordered[0].waitingFor == .question)
        r.apply(ev(.notification(type: "elicitation_dialog"), "e"), at: t0)
        #expect(r.ordered.first { $0.id == "e" }?.waitingFor == .question)
    }

    /// One agent asking for permission outweighs others with questions: that's the one to act on.
    @Test func anyPermissionMakesItAnAlert() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "AskUserQuestion", useID: "u"), "a"), at: t0)
        r.apply(ev(.permissionRequested, "b"), at: t0)
        #expect(PetBrain.baseState(for: r.ordered, now: t0) == .alert)
    }

    @Test func workingAgainClearsTheReason() {
        var r = SessionRegistry()
        r.apply(ev(.permissionRequested), at: t0)
        r.apply(ev(.toolFinished(name: "Bash", useID: nil)), at: t0)
        #expect(r.ordered[0].waitingFor == nil)
    }

    @Test func questionsPeekOutFromHomeLikeAlerts() {
        #expect(PetBrain.homeState(for: .question, doNotDisturb: false) == .peekHold)
        #expect(PetBrain.homeState(for: .question, doNotDisturb: true) == .burrowed)
    }
}

@Suite struct LimitMomentsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func window(_ used: Double, resetsIn: Double) -> LimitWindow { LimitWindow(usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn)) }

    @Test func aReachedLimitShowsSpent() {
        let spent = UsageLimits(fiveHour: window(100, resetsIn: 3600), sevenDay: window(40, resetsIn: 86400), observedAt: now)
        #expect(spent.isSpent)
        #expect(PetBrain.baseState(for: [], limits: spent, now: now) == .exhausted)
        let low = UsageLimits(fiveHour: window(90, resetsIn: 3600), sevenDay: nil, observedAt: now)
        #expect(!low.isSpent)
        #expect(PetBrain.baseState(for: [], limits: low, now: now) == .lowLimit)
    }

    /// The 5-hour window that had been used went away (reset) or was replaced by a fresh one.
    @Test func refillIsAWindowResetAfterRealUse() {
        let used = window(60, resetsIn: 10)
        #expect(UsageLimits.refilled(before: used, after: nil))
        #expect(UsageLimits.refilled(before: used, after: window(2, resetsIn: 5 * 3600)))
        #expect(!UsageLimits.refilled(before: window(3, resetsIn: 10), after: nil), "barely used: nothing to celebrate")
        #expect(!UsageLimits.refilled(before: used, after: window(65, resetsIn: 10)), "same window, more use")
        #expect(!UsageLimits.refilled(before: nil, after: window(0, resetsIn: 3600)))
        // Two sources reporting the same window a few seconds apart, rounding differently: not a reset.
        #expect(!UsageLimits.refilled(before: window(12, resetsIn: 3600), after: window(11.6, resetsIn: 3605)))
    }

    /// Agents still at work means the limit didn't stop them: no lying spent, just the low-limit warning
    /// (which outranks plain working, as before).
    @Test func workingAgentsAreNotSpent() {
        let spent = UsageLimits(fiveHour: window(100, resetsIn: 3600), sevenDay: nil, observedAt: now)
        var s = AgentSession(id: "a", firstSeenAt: now, lastEventAt: now)
        s.status = .working
        #expect(PetBrain.baseState(for: [s], limits: spent, now: now) == .lowLimit)
    }
}

@Suite struct ThrowAndShakeTests {
    let screen = PetScreen(frame: PetRect(x: 0, y: 0, width: 1000, height: 800),
                           visible: PetRect(x: 0, y: 0, width: 1000, height: 780))
    let size = PetSize(width: 128, height: 128)

    @Test func hardThrowsAreFast() {
        #expect(Placement.isHardThrow(PetPoint(x: 1500, y: 0)))
        #expect(Placement.isHardThrow(PetPoint(x: -900, y: 900)))
        #expect(!Placement.isHardThrow(PetPoint(x: 300, y: 200)))
    }

    @Test func aThrowIntoTheSideHitsTheWall() {
        let right = Placement.throwOutcome(from: PetPoint(x: 700, y: 300), velocity: PetPoint(x: 4000, y: 0), size: size, screens: [screen])
        #expect(right.wall == .right)
        #expect(right.destination.x == 1000 - 128)
        let left = Placement.throwOutcome(from: PetPoint(x: 200, y: 300), velocity: PetPoint(x: -4000, y: 0), size: size, screens: [screen])
        #expect(left.wall == .left)
        let free = Placement.throwOutcome(from: PetPoint(x: 300, y: 300), velocity: PetPoint(x: 1500, y: 0), size: size, screens: [screen])
        #expect(free.wall == nil)
    }

    /// Let go gently while hanging over the edge (or over a side Dock): no splat, just a landing.
    @Test func aSoftDropAtTheEdgeIsNoSplat() {
        let gentle = Placement.throwOutcome(from: PetPoint(x: 1000 - 60, y: 300), velocity: PetPoint(x: 5, y: 0), size: size, screens: [screen])
        #expect(gentle.wall == nil)
    }

    /// The first turn of a shake is measured from where the drag started, not from the screen's left edge.
    @Test func jitterFarFromTheOriginIsNoShake() {
        var t = DragTracker(start: PetPoint(x: 800, y: 300), time: 0)
        var time = 0.0
        for k in 0..<12 { time += 0.05; t.move(to: PetPoint(x: 800 + Double(k % 2) * 3, y: 300), time: time) }
        #expect(!t.isShaken)
    }

    /// Back and forth several times, quickly: shaken. A long drag one way is not.
    @Test func shakingIsSeveralQuickReversals() {
        var t = DragTracker(start: PetPoint(x: 0, y: 0), time: 0)
        var x = 0.0, time = 0.0
        for k in 0..<6 {
            for _ in 0..<4 { x += k % 2 == 0 ? 15 : -15; time += 0.02; t.move(to: PetPoint(x: x, y: 0), time: time) }
        }
        #expect(t.isShaken)
        var straight = DragTracker(start: PetPoint(x: 0, y: 0), time: 0)
        for k in 1...40 { straight.move(to: PetPoint(x: Double(k) * 10, y: 0), time: Double(k) * 0.02) }
        #expect(!straight.isShaken)
        var slow = DragTracker(start: PetPoint(x: 0, y: 0), time: 0)
        for k in 0..<6 {
            slow.move(to: PetPoint(x: k % 2 == 0 ? 60 : 0, y: 0), time: Double(k) * 1.0)
        }
        #expect(!slow.isShaken, "reversals spread over seconds aren't a shake")
    }
}

@Suite struct PowerAndNightTests {
    @Test func lowBatteryOnlyOffThePlug() {
        #expect(PowerReading(percent: 15, onAC: false).isLow)
        #expect(!PowerReading(percent: 15, onAC: true).isLow)
        #expect(!PowerReading(percent: 50, onAC: false).isLow)
        #expect(!PowerReading(percent: nil, onAC: false).isLow, "no battery (a desktop Mac)")
    }

    @Test func pluggingInIsNoticed() {
        let off = PowerReading(percent: 40, onAC: false), on = PowerReading(percent: 40, onAC: true)
        #expect(PowerReading.pluggedIn(from: off, to: on))
        #expect(!PowerReading.pluggedIn(from: on, to: on))
        #expect(!PowerReading.pluggedIn(from: nil, to: on), "not at launch")
        #expect(!PowerReading.pluggedIn(from: PowerReading(percent: nil, onAC: false), to: PowerReading(percent: nil, onAC: true)))
    }

    func date(_ h: Int, _ m: Int = 0) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 19; c.hour = h; c.minute = m
        return Calendar.current.date(from: c)!
    }

    /// Local time: the Mac's own clock and time zone.
    @Test func lateNightIsFromTenToFive() {
        #expect(NightDesk.isLate(at: date(22)))
        #expect(NightDesk.isLate(at: date(23, 30)))
        #expect(NightDesk.isLate(at: date(2)))
        #expect(!NightDesk.isLate(at: date(5)))
        #expect(!NightDesk.isLate(at: date(21, 59)))
    }

    @Test func nextChangeIsTheNearestBoundary() {
        #expect(NightDesk.nextChange(after: date(14)) == date(22))
        #expect(NightDesk.nextChange(after: date(23, 30)) == Calendar.current.date(byAdding: .hour, value: 6, to: date(23))!)
        #expect(NightDesk.nextChange(after: date(3)) == date(5))
    }
}

@Suite struct CompactionTests {
    @Test func preCompactHookIsCompaction() {
        let data = Data(#"{"hook_event_name":"PreCompact","session_id":"s","trigger":"auto"}"#.utf8)
        #expect(AgentEvent.parse(data)?.kind == .compacting)
        #expect(HookSettings.events.contains("PreCompact"))
    }

    @Test func registryReportsCompactionWithoutChangingState() {
        var r = SessionRegistry()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .promptSubmitted), at: t0)
        #expect(r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .compacting), at: t0) == .compacted)
        #expect(r.ordered[0].status == .working)
    }

    @Test func codexCompactedLineIsCompaction() {
        var r = CodexRollout(fileName: "rollout-2026-10-16T15-36-45-01a144b6-fc33-7231-a0da-63a9a29ce005.jsonl")
        let line = #"{"timestamp":"2026-10-16T12:38:22.773Z","type":"compacted","payload":{"message":""}}"#
        let kinds = r.read(line).compactMap { if case .event(let e, _) = $0 { e.kind } else { nil } }
        #expect(kinds == [.compacting])
    }

    /// Installs from before PreCompact existed get it added at launch, without a reconnect.
    @Test func olderInstallsAreUpgraded() throws {
        let cmd = "'/x/pixelpet-hook'"
        let old = try HookSettings.install(into: [:], command: cmd, events: HookSettings.previousEvents)
        #expect(!HookSettings.isInstalled(in: old, command: cmd))
        #expect(HookSettings.isOlderInstall(in: old, command: cmd))
        let upgraded = try HookSettings.install(into: old, command: cmd)
        #expect(HookSettings.isInstalled(in: upgraded, command: cmd))
        #expect(!HookSettings.isOlderInstall(in: upgraded, command: cmd))
        #expect(!HookSettings.isOlderInstall(in: [:], command: cmd))
    }

    /// An event the user took out by hand stays out: only exactly the previous set is upgraded.
    @Test func handEditedInstallsAreLeftAlone() throws {
        let cmd = "'/x/pixelpet-hook'"
        let edited = try HookSettings.install(into: [:], command: cmd, events: HookSettings.events.filter { $0 != "Notification" })
        #expect(!HookSettings.isOlderInstall(in: edited, command: cmd))
    }

    @Test func subagentCountAddsUpSessions() {
        var a = AgentSession(id: "a", firstSeenAt: Date(), lastEventAt: Date())
        a.subagents = ["x", "y"]
        var b = AgentSession(id: "b", firstSeenAt: Date(), lastEventAt: Date())
        b.subagents = ["z"]
        #expect(PetBrain.subagentCount([a, b]) == 3)
    }
}

@Suite struct SubagentMomentsTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func spawnThenRecallAfterRealWork() {
        var m = SubagentMoments()
        #expect(m.update(count: 2, now: at(0)) == .spawn)
        #expect(m.update(count: 2, now: at(3)) == nil)
        #expect(m.update(count: 0, now: at(20)) == .recall)
    }

    /// Quick subagents coming and going don't make the copies flicker in and out.
    @Test func shortBurstsAreDebounced() {
        var m = SubagentMoments()
        #expect(m.update(count: 1, now: at(0)) == .spawn)
        #expect(m.update(count: 0, now: at(1)) == nil, "gone too fast to call back")
        #expect(m.update(count: 1, now: at(2)) == nil, "spawned moments ago")
        #expect(m.update(count: 0, now: at(3)) == nil)
        #expect(m.update(count: 1, now: at(40)) == .spawn)
    }

    /// Subagents cleared by bookkeeping (a new prompt) without a spawn shown first: nothing to call back.
    @Test func noRecallWithoutASpawn() {
        var m = SubagentMoments()
        m.prime(count: 3)
        #expect(m.update(count: 0, now: at(10)) == nil)
    }
}

@Suite struct BreaksTests {
    @Test func hookahOnlyWhenAllowedAndNotEveryTime() {
        let rolls = 0..<100
        let allowed = rolls.map { Breaks.fidget(hookahAllowed: true, roll: $0, cloudRoll: 1) }
        let hookahs = allowed.filter { $0 == .hookah || $0 == .hookahCloud }.count
        #expect(hookahs == 25)
        #expect(allowed.contains(.yawn) && allowed.contains(.tumble))
        #expect(!rolls.map { Breaks.fidget(hookahAllowed: false, roll: $0, cloudRoll: 0) }.contains { $0 == .hookah || $0 == .hookahCloud })
    }

    /// LM catches a drop or melts where the cube would roll; the yawns and hookahs stay the same.
    @Test func lidManDripsOrMeltsInsteadOfRolling() {
        let rolls = 0..<100
        let cube = rolls.map { Breaks.fidget(hookahAllowed: true, roll: $0, cloudRoll: 1) }
        let lm = rolls.map { Breaks.fidget(hookahAllowed: true, roll: $0, cloudRoll: 1, lidMan: true) }
        #expect(!lm.contains(.tumble))
        #expect(lm.contains(.drip) && lm.contains(.melt))
        for (a, b) in zip(cube, lm) {
            if a == .tumble { #expect(b == .drip || b == .melt) } else { #expect(a == b) }
        }
    }

    /// A sixth of the non-hookah fidgets are a sneeze, for both figures.
    @Test func aSneezeNowAndThen() {
        let rolls = 0..<600
        for lm in [false, true] {
            let breaks = rolls.map { Breaks.fidget(hookahAllowed: false, roll: $0, cloudRoll: 1, lidMan: lm) }
            #expect(breaks.filter { $0 == .sneeze }.count == 100)
        }
    }

    @Test func aCloudNowAndThen() {
        let breaks = (0..<100).map { Breaks.hookah(cloudRoll: $0) }
        #expect(breaks.filter { $0 == .hookahCloud }.count == 25)
    }
}
