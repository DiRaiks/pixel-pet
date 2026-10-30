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

    /// Answered in Claude Code while the pet held the request: no hook says how, so back to working, and a
    /// denial that stopped the turn settles after the quiet timeout like any interrupt.
    @Test func permissionSettledElsewhereStopsWaiting() {
        var r = SessionRegistry()
        r.apply(ev(.toolStarted(name: "mcp__terminal__run", useID: "t1")), at: t0)
        r.apply(ev(.permissionRequested), at: at(1))
        r.apply(ev(.notification(type: "permission_prompt")), at: at(1))
        r.apply(ev(.permissionSettled), at: at(5))
        #expect(r.ordered[0].status == .working)
        #expect(r.ordered[0].currentTool == nil)
        r.prune(now: at(5 + SessionRegistry.silentWorkTimeout + 1))
        #expect(r.ordered[0].status == .idle)
        // Only a permission wait is settled; a question stays.
        r.apply(ev(.toolStarted(name: "AskUserQuestion", useID: "q1")), at: at(400))
        r.apply(ev(.permissionSettled), at: at(401))
        #expect(r.ordered[0].status == .waiting)
    }

    /// The step running now, its own clock, and the turn's length and step count.
    @Test func stepsAndTurnTime() {
        var r = SessionRegistry()
        func started(_ tool: String, _ object: String, _ id: String) -> AgentEvent {
            AgentEvent(sessionID: "s1", cwd: "/w/proj", kind: .toolStarted(name: tool, useID: id),
                       step: AgentStep(action: .run, object: object))
        }
        r.apply(ev(.promptSubmitted), at: t0)
        #expect(r.ordered[0].turnStartedAt == t0)
        #expect(r.ordered[0].step == nil)
        r.apply(started("Bash", "npm test", "t1"), at: at(5))
        #expect(r.ordered[0].step?.object == "npm test")
        #expect(r.ordered[0].stepSince == at(5))
        #expect(r.ordered[0].steps == 1)
        r.apply(ev(.toolFinished(name: "Bash", useID: "t1")), at: at(9))
        // Between calls: thinking, on a new clock.
        #expect(r.ordered[0].step == nil)
        #expect(r.ordered[0].stepSince == at(9))
        r.apply(started("Bash", "ls", "t2"), at: at(12))
        #expect(r.ordered[0].steps == 2)
        r.apply(ev(.stopped), at: at(100))
        #expect(r.ordered[0].lastTurn == 100)
        #expect(r.ordered[0].step == nil)
        #expect(r.ordered[0].steps == 0)
        // A question isn't a step.
        r.apply(ev(.promptSubmitted), at: at(200))
        r.apply(AgentEvent(sessionID: "s1", cwd: nil, kind: .toolStarted(name: "AskUserQuestion", useID: "q"),
                           step: AgentStep(action: .tool("AskUserQuestion"), object: nil)), at: at(201))
        #expect(r.ordered[0].steps == 0)
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

    /// A session closed by the app and then resumed keeps its id: a new start or prompt brings it back.
    @Test func resumedSessionComesBack() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.sessionEnded), at: at(1))
        r.apply(ev(.toolStarted(name: "Bash", useID: "late")), at: at(2))
        #expect(r.ordered.isEmpty)
        r.apply(ev(.sessionStart(model: nil)), at: at(100))
        #expect(r.ordered.map(\.id) == ["s1"])
        r.apply(ev(.promptSubmitted), at: at(101))
        #expect(r.ordered[0].status == .working)
        // Ended again, and a prompt alone (no start) also brings it back.
        r.apply(ev(.sessionEnded), at: at(102))
        r.apply(ev(.promptSubmitted), at: at(200))
        #expect(r.ordered[0].status == .working)
    }

    func agentEv(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(sessionID: "s1", cwd: "/w/proj", kind: kind, agentID: "helper") }

    /// The app's post-turn helper runs a tool under the session's id with no end reported: the session stays done.
    @Test func agentToolAfterTheTurnDoesNotRestartWork() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.stopped), at: at(5))
        r.apply(agentEv(.toolStarted(name: "Bash", useID: "t")), at: at(7))
        #expect(r.ordered[0].status == .idle)
        #expect(r.ordered[0].step == nil)
        r.apply(ev(.subagentStopped(id: "helper")), at: at(8))
        #expect(r.ordered[0].status == .idle)
        // The session's own agent picking up again still counts.
        r.apply(ev(.toolStarted(name: "Bash", useID: "u")), at: at(20))
        #expect(r.ordered[0].status == .working)
    }

    /// Nor does it end a wait for the user's answer, or wake a session that hasn't had a prompt yet.
    @Test func agentToolBetweenTurnsLeavesWaitsAndFreshSessionsAlone() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.questionAsked), at: at(1))
        r.apply(ev(.stopped), at: at(2))
        r.apply(agentEv(.toolStarted(name: "Bash", useID: "t")), at: at(3))
        #expect(r.ordered[0].status == .waiting)
        var fresh = SessionRegistry()
        fresh.apply(ev(.sessionStart(model: nil)), at: t0)
        fresh.apply(agentEv(.toolStarted(name: "Bash", useID: "t")), at: at(1))
        #expect(fresh.ordered[0].status == .idle)
    }

    /// Inside a turn, and while background subagents outlive it, their tools count as before.
    @Test func agentToolsInsideATurnStillCount() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.permissionRequested), at: at(1))
        r.apply(agentEv(.toolFinished(name: "Bash", useID: "t")), at: at(2))
        #expect(r.ordered[0].status == .working)
        r.apply(ev(.subagentStarted(id: "bg")), at: at(3))
        r.apply(ev(.stopped), at: at(4))
        r.apply(agentEv(.toolStarted(name: "Read", useID: "r")), at: at(5))
        #expect(r.ordered[0].status == .working)
        #expect(r.ordered[0].currentTool == "Read")
        r.apply(ev(.subagentStopped(id: "bg")), at: at(6))
        #expect(r.ordered[0].status == .idle)
    }

    /// Going quiet is only a guess that the turn was stopped: an agent reporting in afterwards still counts.
    @Test func agentToolAfterTheSilentTimeoutStillCounts() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.prune(now: at(SessionRegistry.silentWorkTimeout + 1))
        #expect(r.ordered[0].status == .idle)
        r.apply(agentEv(.toolStarted(name: "Bash", useID: "t")), at: at(SessionRegistry.silentWorkTimeout + 2))
        #expect(r.ordered[0].status == .working)
    }

    /// A resumed session still ignores stragglers once it has ended again.
    @Test func lateEventsAfterASecondEndAreIgnored() {
        var r = SessionRegistry()
        r.apply(ev(.sessionEnded), at: t0)
        r.apply(ev(.promptSubmitted), at: at(1))
        r.apply(ev(.sessionEnded), at: at(2))
        r.apply(ev(.stopped), at: at(3))
        r.apply(ev(.subagentStopped(id: "summary")), at: at(3))
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

    /// Background subagents outlive the turn: the session keeps working until the last one stops, and only
    /// then finishes (and celebrates by the work done).
    @Test func backgroundSubagentsKeepTheSessionWorkingPastStop() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.subagentStarted(id: "a")), at: at(1))
        r.apply(ev(.subagentStarted(id: "b")), at: at(1))
        #expect(r.apply(ev(.stopped), at: at(30)) == nil)
        #expect(r.ordered[0].status == .working)
        r.apply(ev(.subagentStopped(id: "a")), at: at(60))
        #expect(r.ordered[0].status == .working)
        #expect(r.apply(ev(.subagentStopped(id: "b")), at: at(90)) == .finished)
        #expect(r.ordered[0].status == .idle)
    }

    /// A new message while they run doesn't forget them; the next Stop still waits for them.
    @Test func subagentsSurviveANewPrompt() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.subagentStarted(id: "a")), at: at(1))
        r.apply(ev(.stopped), at: at(5))
        r.apply(ev(.promptSubmitted), at: at(10))
        #expect(r.ordered[0].subagents == ["a"])
        r.apply(ev(.stopped), at: at(15))
        #expect(r.ordered[0].status == .working)
    }

    /// A wait for the user between the turn's end and the last subagent stop doesn't lose the finish.
    @Test func waitDuringBackgroundSubagentsStillFinishes() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.subagentStarted(id: "a")), at: at(1))
        r.apply(ev(.stopped), at: at(30))
        r.apply(ev(.permissionRequested), at: at(40))
        #expect(r.ordered[0].status == .waiting)
        r.apply(ev(.subagentStopped(id: "a")), at: at(50))
        #expect(r.apply(ev(.toolStarted(name: "Bash", useID: "x")), at: at(60)) == .finished)
        #expect(r.ordered[0].status == .idle)
        // Late events after the finish don't celebrate again.
        #expect(r.apply(ev(.subagentStopped(id: "a")), at: at(61)) == nil)
    }

    /// Esc or a failure takes the subagents down with the turn: the next Stop finishes right away.
    @Test func interruptAndFailureForgetSubagents() {
        for end in [AgentEvent.Kind.interrupted, .failed] {
            var r = SessionRegistry()
            r.apply(ev(.promptSubmitted), at: t0)
            r.apply(ev(.subagentStarted(id: "a")), at: at(1))
            r.apply(ev(end), at: at(5))
            #expect(r.ordered[0].subagents.isEmpty)
            r.apply(ev(.promptSubmitted), at: at(10))
            r.apply(ev(.stopped), at: at(40))
            #expect(r.ordered[0].status == .idle, "\(end)")
        }
    }

    /// A turn ending with a question waits for the reply even with subagents still out.
    @Test func questionAtStopWaitsDespiteSubagents() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.subagentStarted(id: "a")), at: at(1))
        r.apply(ev(.questionAsked), at: at(20))
        #expect(r.apply(ev(.stopped), at: at(30)) == nil)
        #expect(r.ordered[0].status == .waiting)
    }

    /// A subagent whose stop never arrives doesn't keep the session busy forever: silence settles it.
    @Test func silenceClearsLeftoverSubagents() {
        var r = SessionRegistry()
        r.apply(ev(.promptSubmitted), at: t0)
        r.apply(ev(.subagentStarted(id: "a")), at: at(1))
        r.apply(ev(.stopped), at: at(5))
        r.prune(now: at(5 + SessionRegistry.silentWorkTimeout + 1))
        #expect(r.ordered[0].status == .idle)
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
