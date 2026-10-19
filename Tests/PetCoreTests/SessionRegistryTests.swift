import Foundation
import Testing
@testable import PetCore

@Suite struct SessionRegistryTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func ev(_ kind: AgentEvent.Kind, _ id: String = "s1") -> AgentEvent { AgentEvent(sessionID: id, cwd: "/w/proj", kind: kind) }

    @Test func anyEventCreatesSessionEvenWithoutSessionStart() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "Bash", useID: "t")), at: t0)
        #expect(r.ordered.map(\.id) == ["s1"])
        #expect(r.ordered[0].status == .working)
        #expect(r.ordered[0].currentTool == "Bash")
        #expect(r.ordered[0].project == "proj")
    }

    @Test func promptThenStopGoesWorkingThenIdle() {
        var r = SessionRegistry()
        r.apply(ev(.sessionStart(model: "m")), at: t0)
        #expect(r.ordered[0].status == .idle)
        r.apply(ev(.promptSubmitted), at: at(1))
        #expect(r.ordered[0].status == .working)
        r.apply(ev(.stopped), at: at(2))
        #expect(r.ordered[0].status == .idle)
        #expect(r.ordered[0].finishedAt == at(2))
        #expect(r.ordered[0].model == "m")
    }

    @Test func longTurnCelebratesShortTurnDoesNot() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        #expect(r.apply(ev(.stopped), at: at(5)) == nil)
        r.apply(ev(.promptSubmitted), at: at(10))
        #expect(r.apply(ev(.stopped), at: at(10 + SessionRegistry.celebrateAfter)) == .finished)
    }

    @Test func permissionRequestWaitsUntilToolFinishes() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "Bash", useID: "t1")), at: t0)
        r.apply(ev(.permissionRequested), at: at(1))
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.toolFinished(name: "Bash", useID: "t1")), at: at(2))
        #expect(r.ordered[0].status == .working)
    }

    @Test func permissionNotificationWaitsUnknownNotificationsDont() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.notification(type: "auth_success")), at: at(1))
        #expect(r.ordered[0].status == .working)
        r.apply(ev(.notification(type: "permission_prompt")), at: at(2))
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.notification(type: "elicitation_dialog"), "s2"), at: at(2))
        #expect(r.sessions["s2"]?.status == .waiting)
    }

    @Test func interactiveToolWaitsForItsOwnResult() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "AskUserQuestion", useID: "q1")), at: t0)
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.toolFinished(name: "AskUserQuestion", useID: "q1")), at: at(30))
        #expect(r.ordered[0].status == .working)
    }

    @Test func failureMarksSessionAndReacts() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        #expect(r.apply(ev(.failed), at: at(1)) == .failed)
        #expect(r.ordered[0].status == .failed)
        #expect(r.ordered[0].failedAt == at(1))
        r.apply(ev(.promptSubmitted), at: at(2))
        #expect(r.ordered[0].status == .working)
        #expect(r.ordered[0].failedAt == nil)
    }

    @Test func subagentsCountOnlyMatchedStarts() {
        var r = SessionRegistry()
        r.apply(ev(.subagentStarted(id: "a")), at: t0)
        r.apply(ev(.subagentStarted(id: "b")), at: t0)
        // The CLI's internal post-turn summary stops without a start: ignored.
        r.apply(ev(.subagentStopped(id: "summary")), at: at(1))
        #expect(r.ordered[0].subagents == ["a", "b"])
        r.apply(ev(.subagentStopped(id: "a")), at: at(2))
        #expect(r.ordered[0].subagents == ["b"])
    }

    @Test func sessionEndRemovesAndPruneDropsStale() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted, "a"), at: t0)
        r.apply(ev(.promptSubmitted, "b"), at: at(1))
        r.apply(ev(.sessionEnded, "a"), at: at(2))
        #expect(r.ordered.map(\.id) == ["b"])
        r.prune(now: at(1 + SessionRegistry.staleAfter - 1))
        #expect(r.ordered.count == 1)
        r.prune(now: at(1 + SessionRegistry.staleAfter + 1))
        #expect(r.ordered.isEmpty)
    }

    @Test func orderIsFirstSeen() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted, "z"), at: t0)
        r.apply(ev(.promptSubmitted, "a"), at: at(1))
        r.apply(ev(.stopped, "z"), at: at(2))
        #expect(r.ordered.map(\.id) == ["z", "a"])
    }
}

@Suite struct SessionRegistryReviewTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func ev(_ kind: AgentEvent.Kind, _ id: String = "s1") -> AgentEvent { AgentEvent(sessionID: id, cwd: "/w/p", kind: kind) }

    @Test func idlePromptMeansTheTurnIsOver() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.notification(type: "idle_prompt")), at: at(1))
        #expect(r.ordered[0].status == .idle)
    }

    @Test func latePostToolUseAfterStopDoesNotReviveSession() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "Bash", useID: "t")), at: t0)
        r.apply(ev(.stopped), at: at(1))
        r.apply(ev(.toolFinished(name: "Bash", useID: "t")), at: at(2))
        #expect(r.ordered[0].status == .idle)
    }

    @Test func silentWorkingSessionWithoutToolGoesIdle() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.prune(now: at(SessionRegistry.silentWorkTimeout + 1))
        #expect(r.ordered[0].status == .idle)
    }

    @Test func longRunningToolKeepsWorking() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "Bash", useID: "t")), at: t0)
        r.prune(now: at(SessionRegistry.silentWorkTimeout + 1))
        #expect(r.ordered[0].status == .working)
    }

    @Test func waitingSessionsAreNeverPrunedAsStale() {
        var r = SessionRegistry()
        r.apply(ev(.permissionRequested), at: t0)
        r.prune(now: at(SessionRegistry.staleAfter * 3))
        #expect(r.ordered.first?.status == .waiting)
    }

    @Test func parallelToolDoesNotAnswerAPendingQuestion() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "AskUserQuestion", useID: "q")), at: t0)
        r.apply(ev(.toolStarted(name: "Read", useID: "r")), at: at(1))
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.toolFinished(name: "Read", useID: "r")), at: at(2))
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.toolFinished(name: "AskUserQuestion", useID: "q")), at: at(3))
        #expect(r.ordered[0].status == .working)
    }

    @Test func eventsAfterSessionEndAreIgnored() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.sessionEnded), at: at(1))
        r.apply(ev(.subagentStopped(id: "summary")), at: at(2))
        #expect(r.ordered.isEmpty)
    }

    @Test func waitingTimeDoesNotCountTowardCelebration() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.permissionRequested), at: at(2))
        r.apply(ev(.toolFinished(name: "Bash", useID: nil)), at: at(300))
        #expect(r.apply(ev(.stopped), at: at(301)) == nil)
    }

    @Test func workBeforeAndAfterWaitingAddsUp() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.permissionRequested), at: at(12))
        r.apply(ev(.toolFinished(name: "Bash", useID: nil)), at: at(100))
        #expect(r.apply(ev(.stopped), at: at(110)) == .finished)
    }

    @Test func newPromptClearsLeftoverSubagents() {
        var r = SessionRegistry()
        r.apply(ev(.subagentStarted(id: "a")), at: t0)
        r.apply(ev(.promptSubmitted), at: at(1))
        #expect(r.ordered[0].subagents.isEmpty)
    }

    @Test func nextExpiryCoversStaleAndSilentWork() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted, "w"), at: t0)
        #expect(r.nextExpiry() == at(SessionRegistry.silentWorkTimeout))
        var idle = SessionRegistry()
        idle.apply(ev(.sessionStart(model: nil), "i"), at: t0)
        #expect(idle.nextExpiry() == at(SessionRegistry.staleAfter))
        var waiting = SessionRegistry()
        waiting.apply(ev(.permissionRequested, "q"), at: t0)
        #expect(waiting.nextExpiry() == nil)
    }
}

@Suite struct TurnEndQuestionTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func ev(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(sessionID: "s1", cwd: "/w/p", kind: kind) }

    @Test func questionAtTurnEndWaitsForReply() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.questionAsked), at: at(30))
        #expect(r.ordered[0].status == .working)
        #expect(r.apply(ev(.stopped), at: at(31)) == nil)
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.promptSubmitted), at: at(60))
        #expect(r.ordered[0].status == .working)
        r.apply(ev(.stopped), at: at(65))
        #expect(r.ordered[0].status == .idle)
    }

    @Test func unansweredQuestionFadesAfterStaleTime() {
        var r = SessionRegistry()
        r.apply(ev(.questionAsked), at: t0)
        r.apply(ev(.stopped), at: at(1))
        #expect(r.nextExpiry() == at(1 + SessionRegistry.staleAfter))
        r.prune(now: at(1 + SessionRegistry.staleAfter + 1))
        #expect(r.ordered.first?.status == .idle)
    }
}
