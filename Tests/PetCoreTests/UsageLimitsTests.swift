import Foundation
import Testing
@testable import PetCore

@Suite struct UsageLimitsTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func parsesRateLimitEventFromStreamJSON() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.07,"resetsAt":1792416600},"seven_day":{"utilization":0.04,"resetsAt":1792688400}}}}"#
        let limits = UsageLimits.fromStreamLine(line, observedAt: now)
        #expect(limits?.fiveHour == LimitWindow(usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1_792_416_600)))
        #expect(limits?.sevenDay == LimitWindow(usedPercent: 4, resetsAt: Date(timeIntervalSince1970: 1_792_688_400)))
        #expect(limits?.observedAt == now)
    }

    @Test func ignoresOtherStreamLines() {
        #expect(UsageLimits.fromStreamLine(#"{"type":"assistant"}"#, observedAt: now) == nil)
        #expect(UsageLimits.fromStreamLine("garbage", observedAt: now) == nil)
        #expect(UsageLimits.fromStreamLine(#"{"type":"rate_limit_event","rate_limit_info":{}}"#, observedAt: now) == nil)
    }

    @Test func newerObservationWinsPerWindow() {
        let old = UsageLimits(fiveHour: LimitWindow(usedPercent: 10, resetsAt: now), sevenDay: LimitWindow(usedPercent: 5, resetsAt: now),
                              observedAt: now)
        let newer = UsageLimits(fiveHour: LimitWindow(usedPercent: 20, resetsAt: now), sevenDay: nil, observedAt: now.addingTimeInterval(60))
        let merged = old.merged(with: newer)
        #expect(merged.fiveHour?.usedPercent == 20)
        #expect(merged.sevenDay?.usedPercent == 5)
        #expect(merged.observedAt == now.addingTimeInterval(60))
        #expect(newer.merged(with: old).fiveHour?.usedPercent == 20)
    }

    @Test func windowsPastTheirResetAreDropped() {
        let limits = UsageLimits(fiveHour: LimitWindow(usedPercent: 90, resetsAt: now.addingTimeInterval(-1)),
                                 sevenDay: LimitWindow(usedPercent: 50, resetsAt: now.addingTimeInterval(100)), observedAt: now)
        let current = limits.current(at: now)
        #expect(current.fiveHour == nil)
        #expect(current.sevenDay?.usedPercent == 50)
        #expect(limits.nextReset(after: now) == now.addingTimeInterval(100))
    }

    @Test func lowThresholds() {
        func limits(_ five: Double?, _ week: Double?) -> UsageLimits {
            UsageLimits(fiveHour: five.map { LimitWindow(usedPercent: $0, resetsAt: now) },
                        sevenDay: week.map { LimitWindow(usedPercent: $0, resetsAt: now) }, observedAt: now)
        }
        #expect(!limits(84, 89).isLow)
        #expect(limits(85, nil).isLow)
        #expect(limits(nil, 90).isLow)
    }

    @Test func drainRowsFollowFiveHourUsage() {
        let half = UsageLimits(fiveHour: LimitWindow(usedPercent: 50, resetsAt: now), sevenDay: nil, observedAt: now)
        #expect(half.drainRows(interior: 12) == 6)
        #expect(UsageLimits(fiveHour: LimitWindow(usedPercent: 140, resetsAt: now), sevenDay: nil, observedAt: now).drainRows(interior: 12) == 12)
        #expect(UsageLimits(fiveHour: nil, sevenDay: nil, observedAt: now).drainRows(interior: 12) == 0)
    }
}

@Suite struct InboundTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func hookPayloadsStayHooks() {
        let inbound = Inbound.parse(Data(#"{"hook_event_name":"Stop","session_id":"s"}"#.utf8), at: now)
        #expect(inbound == .hook(AgentEvent(sessionID: "s", cwd: nil, kind: .stopped)))
    }

    @Test func statuslinePayloadBecomesSnapshot() {
        let json = #"{"session_id":"s","cwd":"/w/p","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"context_window":{"used_percentage":42.4},"rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":1792416600}}}"#
        guard case let .statusline(snapshot) = Inbound.parse(Data(json.utf8), at: now) else {
            Issue.record("expected statusline"); return
        }
        #expect(snapshot.sessionID == "s")
        #expect(snapshot.model == "Opus 5.5")
        #expect(snapshot.contextPercent == 42.4)
        #expect(snapshot.limits?.fiveHour == LimitWindow(usedPercent: 12.5, resetsAt: Date(timeIntervalSince1970: 1_792_416_600)))
        #expect(snapshot.limits?.sevenDay == nil)
    }

    @Test func statuslineWithoutLimitsHasNoLimits() {
        let json = #"{"session_id":"s","model":{"display_name":"Haiku 5.5"},"context_window":{"used_percentage":null}}"#
        guard case let .statusline(snapshot) = Inbound.parse(Data(json.utf8), at: now) else {
            Issue.record("expected statusline"); return
        }
        #expect(snapshot.limits == nil)
        #expect(snapshot.contextPercent == nil)
    }

    @Test func unknownShapesAreDropped() {
        #expect(Inbound.parse(Data(#"{"session_id":"s"}"#.utf8), at: now) == nil)
    }
}

@Suite struct SnapshotRegistryTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func snapshotAddsModelAndContext() {
        var r = SessionRegistry()
        r.apply(StatuslineSnapshot(sessionID: "s", cwd: "/w/p", model: "Opus 5.5", contextPercent: 40, limits: nil), at: t0)
        #expect(r.ordered.first?.model == "Opus 5.5")
        #expect(r.ordered.first?.contextPercent == 40)
        #expect(r.ordered.first?.status == .idle)
    }

    @Test func snapshotForEndedSessionIsIgnored() {
        var r = SessionRegistry()
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .sessionEnded), at: t0)
        r.apply(StatuslineSnapshot(sessionID: "s", cwd: nil, model: "x", contextPercent: 1, limits: nil), at: t0)
        #expect(r.ordered.isEmpty)
    }

    @Test func shortModelNames() {
        #expect(AgentSession.shortModel("claude-opus-5-5") == "Opus")
        #expect(AgentSession.shortModel("Haiku 5.5") == "Haiku")
        #expect(AgentSession.shortModel("some-new-model") == "some-new-model")
        #expect(AgentSession.shortModel(nil) == nil)
    }
}

@Suite struct LowLimitBrainTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func lowLimitBeatsWorkingButNotAlert() {
        var working = AgentSession(id: "w", firstSeenAt: now, lastEventAt: now)
        working.status = .working
        var waiting = AgentSession(id: "q", firstSeenAt: now, lastEventAt: now)
        waiting.status = .waiting
        let low = UsageLimits(fiveHour: LimitWindow(usedPercent: 95, resetsAt: now.addingTimeInterval(100)), sevenDay: nil, observedAt: now)
        #expect(PetBrain.baseState(for: [working], limits: low, now: now) == .lowLimit)
        #expect(PetBrain.baseState(for: [working, waiting], limits: low, now: now) == .alert)
        #expect(PetBrain.baseState(for: [], limits: low, now: now) == .lowLimit)
    }

    @Test func expiredLowLimitIsIgnored() {
        let stale = UsageLimits(fiveHour: LimitWindow(usedPercent: 95, resetsAt: now.addingTimeInterval(-1)), sevenDay: nil, observedAt: now)
        #expect(PetBrain.baseState(for: [], limits: stale, now: now) == .idle)
    }
}

@Suite struct UsageLimitsReviewTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)
    func at(_ s: Double) -> Date { now.addingTimeInterval(s) }

    @Test func statuslineTaggedAsStatusHookIsStillAStatusline() {
        let json = #"{"hook_event_name":"Status","session_id":"s","model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":10}}"#
        guard case .statusline = Inbound.parse(Data(json.utf8), at: now) else {
            Issue.record("expected statusline"); return
        }
    }

    @Test func staleSnapshotDoesNotOverwriteFresherWindow() {
        let probe = UsageLimits(fiveHour: LimitWindow(usedPercent: 60, resetsAt: at(3600)), sevenDay: nil, observedAt: at(0))
        // An idle terminal re-sends an older window: same reset, lower usage.
        let oldSnapshot = UsageLimits(fiveHour: LimitWindow(usedPercent: 40, resetsAt: at(3600)), sevenDay: nil, observedAt: at(10))
        #expect(probe.merged(with: oldSnapshot).fiveHour?.usedPercent == 60)
        #expect(probe.merged(with: oldSnapshot).observedAt == at(0))
    }

    @Test func laterWindowWinsAfterReset() {
        let before = UsageLimits(fiveHour: LimitWindow(usedPercent: 90, resetsAt: at(10)), sevenDay: nil, observedAt: at(0))
        let after = UsageLimits(fiveHour: LimitWindow(usedPercent: 3, resetsAt: at(18_010)), sevenDay: nil, observedAt: at(20))
        #expect(before.merged(with: after).fiveHour?.usedPercent == 3)
        #expect(after.merged(with: before).fiveHour?.usedPercent == 3)
    }

    @Test func sameWindowsIgnoreObservationTime() {
        let a = UsageLimits(fiveHour: LimitWindow(usedPercent: 5, resetsAt: at(10)), sevenDay: nil, observedAt: at(0))
        var b = a
        b.observedAt = at(99)
        #expect(a.sameWindows(as: b))
        b.fiveHour?.usedPercent = 6
        #expect(!a.sameWindows(as: b))
    }
}

@Suite struct ProbePolicyTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)
    func ago(_ s: Double) -> Date { now.addingTimeInterval(-s) }

    @Test func launchProbeSkippedWhenLimitsAreFresh() {
        let p = ProbePolicy()
        #expect(!p.allows(.launch, now: now, limitsObservedAt: ago(60)))
        #expect(p.allows(.launch, now: now, limitsObservedAt: ago(ProbePolicy.freshFor + 1)))
        #expect(p.allows(.launch, now: now, limitsObservedAt: nil))
    }

    @Test func busyAgentsProbeEveryHalfHour() {
        var p = ProbePolicy()
        p.started(at: ago(ProbePolicy.busyInterval - 1))
        p.finished(success: true)
        #expect(!p.allows(.busy, now: now, limitsObservedAt: ago(ProbePolicy.busyInterval - 1)))
        #expect(p.allows(.busy, now: now.addingTimeInterval(2), limitsObservedAt: ago(ProbePolicy.busyInterval + 1)))
    }

    @Test func panelUsesFreshnessAndCooldown() {
        var p = ProbePolicy()
        #expect(!p.allows(.panel, now: now, limitsObservedAt: ago(60)))
        #expect(p.allows(.panel, now: now, limitsObservedAt: ago(ProbePolicy.freshFor + 1)))
        p.started(at: ago(30))
        p.finished(success: false)
        #expect(!p.allows(.panel, now: now, limitsObservedAt: nil))
    }

    @Test func failuresBackOff() {
        var p = ProbePolicy()
        p.started(at: now)
        p.finished(success: false)
        #expect(p.nextAllowed == now.addingTimeInterval(5 * 60))
        p.started(at: now)
        p.finished(success: false)
        #expect(p.nextAllowed == now.addingTimeInterval(15 * 60))
        p.started(at: now)
        p.finished(success: false)
        p.started(at: now)
        p.finished(success: false)
        #expect(p.nextAllowed == now.addingTimeInterval(30 * 60))
        p.started(at: now)
        p.finished(success: true)
        #expect(p.nextAllowed == now.addingTimeInterval(ProbePolicy.manualCooldown))
    }

    @Test func manualRefreshOnlyHasShortCooldownAndRespectsInFlight() {
        var p = ProbePolicy()
        p.started(at: ago(ProbePolicy.manualCooldown + 1))
        #expect(!p.allows(.manual, now: now, limitsObservedAt: nil))
        p.finished(success: true)
        #expect(p.allows(.manual, now: now, limitsObservedAt: ago(5)))
    }
}
