import Foundation
import Testing
@testable import PetCore

@Suite struct ToolKindTests {
    @Test func builtInToolsMapToIcons() {
        #expect(ToolKind(toolName: "Bash") == .run)
        #expect(ToolKind(toolName: "Grep") == .search)
        #expect(ToolKind(toolName: "WebSearch") == .search)
        #expect(ToolKind(toolName: "Read") == .read)
        #expect(ToolKind(toolName: "WebFetch") == .read)
        #expect(ToolKind(toolName: "Edit") == .edit)
        #expect(ToolKind(toolName: "Write") == .edit)
        #expect(ToolKind(toolName: "BashOutput") == .run)
        #expect(ToolKind(toolName: "LS") == .search)
        #expect(ToolKind(toolName: "NotebookRead") == .read)
        #expect(ToolKind(toolName: "Task") == nil)
        #expect(ToolKind(toolName: "mcp__github__create_issue") == nil)
    }

    /// The working session heard from last decides; waiting or toolless sessions don't count.
    @Test func latestWorkingSessionWins() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var r = SessionRegistry()
        r.apply(AgentEvent(sessionID: "a", cwd: nil, kind: .toolStarted(name: "Bash", useID: "1")), at: t0)
        r.apply(AgentEvent(sessionID: "b", cwd: nil, kind: .toolStarted(name: "Edit", useID: "2")), at: t0.addingTimeInterval(5))
        #expect(ToolKind.current(in: r.ordered) == .edit)
        r.apply(AgentEvent(sessionID: "b", cwd: nil, kind: .toolFinished(name: "Edit", useID: "2")), at: t0.addingTimeInterval(6))
        #expect(ToolKind.current(in: r.ordered) == .run)
        r.apply(AgentEvent(sessionID: "a", cwd: nil, kind: .permissionRequested), at: t0.addingTimeInterval(7))
        #expect(ToolKind.current(in: r.ordered) == nil)
    }
}

@Suite struct GitPushTests {
    func pushed(_ command: String, event: String = "PostToolUse", tool: String = "Bash") -> Bool {
        let input = try! JSONSerialization.data(withJSONObject: ["command": command])
        let json = #"{"hook_event_name":"\#(event)","session_id":"s","tool_name":"\#(tool)","tool_use_id":"t","tool_input":\#(String(decoding: input, as: UTF8.self))}"#
        return AgentEvent.parse(Data(json.utf8))?.pushed ?? false
    }

    @Test func successfulPushesCount() {
        #expect(pushed("git push"))
        #expect(pushed("git push -u origin feat/x"))
        #expect(pushed("cd repo && git push origin main 2>&1 | tail -1"))
        #expect(pushed("git -C ~/Work/app push"))
    }

    @Test func otherCommandsAndFailuresDont() {
        #expect(!pushed("git commit -m 'push it'"))
        #expect(!pushed("git pull"))
        #expect(!pushed("git push --dry-run"))
        #expect(!pushed("git push", event: "PostToolUseFailure"))
        #expect(!pushed("git push", event: "PreToolUse"))
        #expect(!pushed("git push", tool: "Read"))
        #expect(!pushed("git push -n origin main"))
        #expect(!pushed(#"git commit -m "docs: explain the git push flow""#))
        #expect(!pushed("echo 'then git push'"))
    }

    @Test func quotedArgumentsStillPush() {
        #expect(pushed(#"git -C "my dir" push"#))
        #expect(pushed(#"git commit -m "wip" && git push"#))
    }
}

@Suite struct PettingTests {
    /// Strokes of `width` points back and forth, one sample per `dt` seconds.
    func rub(_ d: inout PettingDetector, strokes: Int, width: Double = 10, dt: Double = 0.05, from t0: Double = 0) -> Bool {
        var t = t0, petted = false
        for s in 0..<strokes {
            let from = s % 2 == 0 ? 0.0 : width, to = width - from
            for k in 0...4 {
                petted = d.move(x: from + (to - from) * Double(k) / 4, at: t) || petted
                t += dt
            }
        }
        return petted
    }

    @Test func rubbingBackAndForthPets() {
        var d = PettingDetector()
        #expect(rub(&d, strokes: 5))
    }

    @Test func smallWigglesAndSlowSweepsDont() {
        var d = PettingDetector()
        #expect(!rub(&d, strokes: 6, width: 2))
        var slow = PettingDetector()
        #expect(!rub(&slow, strokes: 5, dt: 0.4))
    }

    @Test func notAgainRightAway() {
        var d = PettingDetector()
        #expect(rub(&d, strokes: 5))
        #expect(!rub(&d, strokes: 5, from: 2))
        #expect(rub(&d, strokes: 5, from: 20))
    }
}

@Suite struct HolidayTests {
    func date(_ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))!
    }

    @Test func pumpkinTheLastWeekOfOctoberFirOverNewYear() {
        #expect(Holiday.on(date(10, 24)) == nil)
        #expect(Holiday.on(date(10, 25)) == .halloween)
        #expect(Holiday.on(date(10, 31)) == .halloween)
        #expect(Holiday.on(date(11, 1)) == nil)
        #expect(Holiday.on(date(12, 19)) == nil)
        #expect(Holiday.on(date(12, 20)) == .newYear)
        #expect(Holiday.on(date(1, 7)) == .newYear)
        #expect(Holiday.on(date(1, 8)) == nil)
    }
}

@Suite struct WaitNudgeTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func firstWaveAfterAMinuteThenEveryFortyFive() {
        #expect(WaitNudge.next(since: t0, lastWave: nil) == t0.addingTimeInterval(60))
        #expect(WaitNudge.next(since: t0, lastWave: t0.addingTimeInterval(60)) == t0.addingTimeInterval(105))
        // A wave from an earlier wait doesn't shorten the new one.
        #expect(WaitNudge.next(since: t0, lastWave: t0.addingTimeInterval(-10)) == t0.addingTimeInterval(60))
    }

    @Test func registryKnowsWhenTheWaitBegan() {
        var r = SessionRegistry()
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .promptSubmitted), at: t0)
        #expect(r.ordered[0].waitingSince == nil)
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .permissionRequested), at: t0.addingTimeInterval(5))
        #expect(r.ordered[0].waitingSince == t0.addingTimeInterval(5))
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .notification(type: "permission_prompt")), at: t0.addingTimeInterval(9))
        #expect(r.ordered[0].waitingSince == t0.addingTimeInterval(5))
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .toolStarted(name: "Bash", useID: "x")), at: t0.addingTimeInterval(20))
        #expect(r.ordered[0].waitingSince == nil)
    }
}
