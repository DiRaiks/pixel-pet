import Foundation
import Testing
@testable import PetCore

@Suite struct CodexRolloutTests {
    static let id = "01a144b6-fc33-7231-a0da-63a9a29ce005"
    static let file = "rollout-2026-10-16T15-36-45-\(id).jsonl"

    func line(_ type: String, _ payload: [String: Any], at time: String = "2026-10-16T12:38:22.773Z") -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["timestamp": time, "type": type, "payload": payload])
        return String(decoding: data, as: UTF8.self)
    }

    func meta(threadSource: String? = "user") -> String {
        var p: [String: Any] = ["id": Self.id, "cwd": "/Users/me/Work/pixel-pet", "originator": "codex_work_desktop"]
        if let threadSource { p["thread_source"] = threadSource }
        return line("session_meta", p)
    }

    func event(_ type: String, _ extra: [String: Any] = [:], at time: String = "2026-10-16T12:38:22.773Z") -> String {
        line("event_msg", extra.merging(["type": type]) { a, _ in a }, at: time)
    }

    func events(_ outputs: [CodexRollout.Output]) -> [AgentEvent.Kind] {
        outputs.compactMap { if case .event(let e, _) = $0 { e.kind } else { nil } }
    }

    @Test func metaOpensTheSessionWithItsFolder() {
        var r = CodexRollout(fileName: Self.file)
        let out = r.read(meta())
        guard case .event(let e, _) = out.first else { Issue.record("no event"); return }
        #expect(e.sessionID == Self.id)
        #expect(e.cwd == "/Users/me/Work/pixel-pet")
        #expect(e.kind == .sessionStart(model: nil))
    }

    @Test func turnsMapToPromptAndStop() {
        var r = CodexRollout(fileName: Self.file)
        _ = r.read(meta())
        #expect(events(r.read(event("task_started", ["turn_id": "t1"]))) == [.promptSubmitted])
        #expect(events(r.read(event("task_complete", ["turn_id": "t1", "duration_ms": 42_000]))) == [.stopped])
        #expect(events(r.read(event("turn_aborted", ["turn_id": "t2"]))) == [.interrupted])
        #expect(events(r.read(event("error", ["message": "boom"]))) == [.failed])
    }

    /// Anything carrying a turn id inside a turn says the agent is still at it (a long command, reasoning).
    @Test func turnScopedLinesKeepItWorking() {
        var r = CodexRollout(fileName: Self.file)
        #expect(events(r.read(event("item_completed", ["turn_id": "t1", "item": ["type": "Reasoning"]]))) == [.stillWorking])
        #expect(events(r.read(line("token_usage_record", ["turn_id": "t1"]))) == [.stillWorking])
        // Lines outside any turn don't.
        var idle = CodexRollout(fileName: Self.file)
        #expect(events(idle.read(event("thread_settings_applied", ["thread_id": "x"]))).isEmpty)
        #expect(events(idle.read(line("response_item", ["type": "message"]))).isEmpty)
    }

    /// Read from the tail, the session id comes from the file name and the folder from the turn context.
    @Test func tailWithoutMetaUsesFileNameAndTurnContext() {
        var r = CodexRollout(fileName: Self.file)
        let out = r.read(line("turn_context", ["turn_id": "t1", "cwd": "/w/app", "model": "gpt-5.5-codex"]))
        guard case .event(let e, _) = out.first else { Issue.record("no event"); return }
        #expect(e.sessionID == Self.id)
        #expect(e.cwd == "/w/app")
        #expect(e.kind == .sessionStart(model: "gpt-5.5-codex"))
    }

    /// A finished or aborted turn stays finished, whatever late line of it comes after.
    @Test func closedTurnIsNotRevivedByItsLateLines() {
        var r = CodexRollout(fileName: Self.file)
        _ = r.read(event("task_started", ["turn_id": "t1"]))
        _ = r.read(event("task_complete", ["turn_id": "t1"]))
        #expect(events(r.read(line("token_usage_record", ["turn_id": "t1"]))).isEmpty)
        _ = r.read(event("task_started", ["turn_id": "t2"]))
        _ = r.read(event("turn_aborted", ["turn_id": "t2"]))
        #expect(events(r.read(event("item_completed", ["turn_id": "t2"]))).isEmpty)
        // A new turn's lines still count.
        #expect(events(r.read(event("item_completed", ["turn_id": "t3"]))) == [.stillWorking])
    }

    /// Inside an open turn every line is a sign of life, also ones without a turn id (tool calls, messages).
    @Test func anyLineInsideAnOpenTurnKeepsItWorking() {
        var r = CodexRollout(fileName: Self.file)
        _ = r.read(event("task_started", ["turn_id": "t1"]))
        #expect(events(r.read(line("response_item", ["type": "function_call"]))) == [.stillWorking])
        _ = r.read(event("task_complete", ["turn_id": "t1"]))
        #expect(events(r.read(line("response_item", ["type": "message"]))).isEmpty)
    }

    /// Reactions belong to what just happened, not to turns found in a file read late.
    @Test func onlyRecentEventsAreLive() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(CodexRollout.isLive(now.addingTimeInterval(-2), now: now))
        #expect(!CodexRollout.isLive(now.addingTimeInterval(-CodexRollout.liveWindow - 1), now: now))
    }

    @Test func windowsWithoutLengthFallBackToTheirKeys() {
        let limits = CodexRollout.limits([
            "primary": ["used_percent": 5.0, "resets_at": 100],
            "secondary": ["used_percent": 50.0, "resets_at": 200],
        ], Date())
        #expect(limits?.fiveHour?.usedPercent == 5)
        #expect(limits?.sevenDay?.usedPercent == 50)
    }

    @Test func eventsCarryTheirOwnTime() {
        var r = CodexRollout(fileName: Self.file)
        let out = r.read(event("task_started", ["turn_id": "t1"], at: "2026-10-16T12:47:30.624Z"))
        guard case .event(_, let at) = out.first else { Issue.record("no event"); return }
        #expect(abs(at.timeIntervalSince1970 - 1_792_154_850.624) < 0.001)
    }

    @Test func tokenCountReportsLimits() {
        var r = CodexRollout(fileName: Self.file)
        let limits: [String: Any] = [
            "primary": ["used_percent": 12.5, "window_minutes": 300, "resets_at": 1_792_172_304],
            "secondary": ["used_percent": 40.0, "window_minutes": 10080, "resets_at": 1_792_759_104],
        ]
        let out = r.read(event("token_count", ["rate_limits": limits]))
        guard case .limits(let l) = out.first else { Issue.record("no limits"); return }
        #expect(l.fiveHour == LimitWindow(usedPercent: 12.5, resetsAt: Date(timeIntervalSince1970: 1_792_172_304)))
        #expect(l.sevenDay?.usedPercent == 40)
    }

    @Test func emptyRateLimitsAreIgnored() {
        var r = CodexRollout(fileName: Self.file)
        #expect(r.read(event("token_count", ["rate_limits": NSNull()])).isEmpty)
        #expect(r.read(event("token_count", ["info": ["x": 1]])).isEmpty)
    }

    /// Subagent threads write their own rollouts; they belong to their parent, not to the stack.
    @Test func subagentThreadsAreSkipped() {
        var r = CodexRollout(fileName: Self.file)
        #expect(r.read(meta(threadSource: "subagent")).isEmpty)
        #expect(r.read(event("task_started", ["turn_id": "t1"])).isEmpty)
    }

    @Test func brokenLinesAreIgnored() {
        var r = CodexRollout(fileName: Self.file)
        #expect(r.read("{\"timestamp\": \"2026").isEmpty)
        #expect(r.read("").isEmpty)
        #expect(CodexRollout(fileName: "notes.jsonl").sessionIDFromFileName == nil)
    }
}

@Suite struct CodexAppServerTests {
    @Test func rateLimitsResponseBecomesLimits() {
        let line = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":300,"resetsAt":1792436474},"secondary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1793023274},"planType":"team"}}}"#
        let limits = CodexRollout.appServerLimits(line, id: 2, observedAt: Date(timeIntervalSince1970: 5))
        #expect(limits?.fiveHour == LimitWindow(usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1_792_436_474)))
        #expect(limits?.sevenDay?.usedPercent == 31)
        #expect(limits?.observedAt == Date(timeIntervalSince1970: 5))
    }

    @Test func answerIsMatchedByExactID() {
        #expect(CodexRollout.isResponse(#"{"id":2,"error":{"message":"x"}}"#, id: 2))
        #expect(!CodexRollout.isResponse(#"{"id":20,"result":{}}"#, id: 2))
        #expect(!CodexRollout.isResponse(#"{"method":"x","params":{"id":2}}"#, id: 2))
    }

    @Test func otherLinesAreNotLimits() {
        #expect(CodexRollout.appServerLimits(#"{"id":1,"result":{"userAgent":"x"}}"#, id: 2, observedAt: Date()) == nil)
        #expect(CodexRollout.appServerLimits(#"{"method":"remoteControl/status/changed","params":{}}"#, id: 2, observedAt: Date()) == nil)
        #expect(CodexRollout.appServerLimits(#"{"id":2,"error":{"message":"not logged in"}}"#, id: 2, observedAt: Date()) == nil)
    }
}

@Suite struct CodexRegistryTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func ev(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(sessionID: "c1", cwd: "/w/app", kind: kind) }

    @Test func interruptedTurnGoesIdleWithoutCelebrating() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        #expect(r.apply(ev(.interrupted), at: t0.addingTimeInterval(SessionRegistry.bigFinishAfter + 1)) == nil)
        #expect(r.ordered[0].status == .idle)
        #expect(r.ordered[0].finishedAt == nil)
    }

    /// Codex writes an abort when the user stops a turn, so its sessions don't need the silent-work timeout:
    /// a long build stays "working" however quiet it is.
    @Test func registryWithoutSilentTimeoutKeepsQuietTurnsWorking() {
        var r = SessionRegistry(silentWorkTimeout: nil)
        r.apply(ev(.promptSubmitted), at: t0)
        r.prune(now: t0.addingTimeInterval(SessionRegistry.silentWorkTimeout * 3))
        #expect(r.ordered[0].status == .working)
        #expect(r.nextExpiry() == t0.addingTimeInterval(SessionRegistry.staleAfter))
    }

    @Test func stillWorkingDoesNotHideAFailure() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.failed), at: t0.addingTimeInterval(1))
        r.apply(ev(.stillWorking), at: t0.addingTimeInterval(2))
        #expect(r.ordered[0].status == .failed)
    }

    /// A long command can outlast the silent-work timeout; its next line brings the session back to working
    /// without losing the time already worked.
    @Test func stillWorkingRevivesATimedOutTurn() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.stillWorking), at: t0.addingTimeInterval(60))
        #expect(r.ordered[0].workingSince == t0)
        r.prune(now: t0.addingTimeInterval(60 + SessionRegistry.silentWorkTimeout + 1))
        #expect(r.ordered[0].status == .idle)
        r.apply(ev(.stillWorking), at: t0.addingTimeInterval(500))
        #expect(r.ordered[0].status == .working)
    }
}
