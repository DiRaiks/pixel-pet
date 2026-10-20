import Foundation
@testable import PetCore
import Testing

struct AgentNoticeTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    func ev(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(sessionID: "s1", cwd: "/w/p", kind: kind) }

    /// Applies events one by one and collects what each would do to the session's notification.
    func plan(_ events: [(AgentEvent, TimeInterval)]) -> [NoticePlan.Action?] {
        var r = SessionRegistry()
        return events.map { event, time in
            let before = r.sessions["s1"]
            let reaction = r.apply(event, at: at(time))
            return NoticePlan.action(before: before, after: r.sessions["s1"], reaction: reaction)
        }
    }

    @Test func waitsPostAndAnswersClear() {
        let actions = plan([
            (ev(.promptSubmitted), 0),
            (ev(.toolStarted(name: "Bash", useID: "t1")), 1),
            (ev(.permissionRequested), 2),
            (ev(.notification(type: "permission_prompt")), 2),
            (ev(.toolFinished(name: "Bash", useID: "t1")), 9),
        ])
        #expect(actions == [.clear, nil, .post(.permission), nil, .clear])
    }

    @Test func aLongTurnPostsFinishedAQuickOneDoesnt() {
        let long = plan([(ev(.promptSubmitted), 0), (ev(.toolStarted(name: "Bash", useID: "t")), 1), (ev(.stopped), 120)])
        #expect(long.last == .post(.finished(took: 120, steps: 0)))
        let quick = plan([(ev(.promptSubmitted), 0), (ev(.stopped), 5)])
        #expect(quick.last == .some(nil))
    }

    @Test func questionsFailuresAndEndedSessions() {
        let asked = plan([(ev(.promptSubmitted), 0), (ev(.toolStarted(name: "AskUserQuestion", useID: "q")), 1)])
        #expect(asked.last == .post(.question))
        let failed = plan([(ev(.promptSubmitted), 0), (ev(.failed), 3)])
        #expect(failed.last == .post(.failed))
        let ended = plan([(ev(.promptSubmitted), 0), (ev(.sessionEnded), 3)])
        #expect(ended.last == .clear)
    }

    @Test func whoGetsToPost() {
        #expect(!NoticePlan.posts(mode: .off, petVisible: false, doNotDisturb: false))
        #expect(NoticePlan.posts(mode: .whenHidden, petVisible: false, doNotDisturb: false))
        #expect(!NoticePlan.posts(mode: .whenHidden, petVisible: true, doNotDisturb: false))
        #expect(NoticePlan.posts(mode: .always, petVisible: true, doNotDisturb: false))
        #expect(!NoticePlan.posts(mode: .always, petVisible: false, doNotDisturb: true))
    }

    @Test func eventsCarryTheirHost() {
        let data = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "UserPromptSubmit", "session_id": "s",
                                                                "pixelpet_app": "", "pixelpet_term": "Apple_Terminal"])
        #expect(AgentEvent.parse(data)?.host?.bundleID == "com.apple.Terminal")
        var r = SessionRegistry()
        r.apply(AgentEvent.parse(data)!, at: t0)
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .stopped), at: at(1))
        #expect(r.sessions["s"]?.host?.bundleID == "com.apple.Terminal")
    }
}
