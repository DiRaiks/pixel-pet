import Foundation
import Testing
@testable import PetCore

@Suite struct AgentEventTests {
    func parse(_ json: String) -> AgentEvent? { AgentEvent.parse(Data(json.utf8)) }

    @Test func parsesSessionStartWithModelAndCwd() {
        let e = parse(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/Users/a/Work/pixel-pet","source":"startup","model":"claude-haiku-5-5"}"#)
        #expect(e == AgentEvent(sessionID: "s1", cwd: "/Users/a/Work/pixel-pet", kind: .sessionStart(model: "claude-haiku-5-5")))
    }

    @Test func parsesToolEventsWithUseID() {
        #expect(parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"ls"}}"#)?.kind
            == .toolStarted(name: "Bash", useID: "t1"))
        #expect(parse(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"t1"}"#)?.kind
            == .toolFinished(name: "Bash", useID: "t1"))
        #expect(parse(#"{"hook_event_name":"PostToolUseFailure","session_id":"s","tool_name":"Bash","tool_use_id":"t1"}"#)?.kind
            == .toolFinished(name: "Bash", useID: "t1"))
    }

    @Test func parsesLifecycleEvents() {
        #expect(parse(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","prompt":"secret"}"#)?.kind == .promptSubmitted)
        #expect(parse(#"{"hook_event_name":"Stop","session_id":"s"}"#)?.kind == .stopped)
        #expect(parse(#"{"hook_event_name":"StopFailure","session_id":"s"}"#)?.kind == .failed)
        #expect(parse(#"{"hook_event_name":"PermissionRequest","session_id":"s"}"#)?.kind == .permissionRequested)
        #expect(parse(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"permission_prompt"}"#)?.kind
            == .notification(type: "permission_prompt"))
        #expect(parse(#"{"hook_event_name":"SubagentStart","session_id":"s","agent_id":"a1"}"#)?.kind == .subagentStarted(id: "a1"))
        #expect(parse(#"{"hook_event_name":"SubagentStop","session_id":"s","agent_id":"a1"}"#)?.kind == .subagentStopped(id: "a1"))
        #expect(parse(#"{"hook_event_name":"SessionEnd","session_id":"s","reason":"exit"}"#)?.kind == .sessionEnded)
    }

    @Test func rejectsUnknownMalformedOrAnonymousEvents() {
        #expect(parse(#"{"hook_event_name":"PostCompact","session_id":"s"}"#) == nil)
        #expect(parse(#"{"hook_event_name":"Stop"}"#) == nil)
        #expect(parse("not json") == nil)
        #expect(parse(#"["array"]"#) == nil)
    }

    @Test func projectNameIsLastPathComponent() {
        #expect(AgentSession.projectName(for: "/Users/a/Work/pixel-pet") == "pixel-pet")
        #expect(AgentSession.projectName(for: nil) == nil)
    }
}

@Suite struct QuestionEventTests {
    func parse(_ json: String) -> AgentEvent? { AgentEvent.parse(Data(json.utf8)) }

    @Test func turnEndQuestionIsRecognized() {
        let e = parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"mcp__ccd_turn__wrap_up","tool_use_id":"w","tool_input":{"recap":"r","ask":"Коммитим?","actions":[]}}"#)
        #expect(e?.kind == .questionAsked)
    }

    @Test func turnEndWithoutQuestionIsAPlainTool() {
        let e = parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"mcp__ccd_turn__wrap_up","tool_use_id":"w","tool_input":{"recap":"r"}}"#)
        #expect(e?.kind == .toolStarted(name: "mcp__ccd_turn__wrap_up", useID: "w"))
        let blank = parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"mcp__ccd_turn__wrap_up","tool_input":{"ask":"  "}}"#)
        #expect(blank?.kind == .toolStarted(name: "mcp__ccd_turn__wrap_up", useID: nil))
    }

    @Test func logLineHasNoContent() {
        let e = AgentEvent(sessionID: "7d34aa38-5817", cwd: "/Users/a/secret-project", kind: .toolStarted(name: "Bash", useID: "t"))
        #expect(e.logLine == "7d34aa38 secret-project toolStarted Bash")
        let sub = AgentEvent(sessionID: "7d34aa38-5817", cwd: "/Users/a/secret-project", kind: .toolStarted(name: "Bash", useID: "t"),
                             agentID: "a1")
        #expect(sub.logLine == "7d34aa38 secret-project toolStarted Bash [agent]")
    }

    /// Tool calls inside a subagent carry its id; the session's own agent sends none.
    @Test func parsesTheSubagentAToolRunsIn() {
        let inside = parse(#"{"hook_event_name":"PreToolUse","session_id":"s","agent_id":"a1","agent_type":"Explore","tool_name":"Bash","tool_input":{"command":"true"}}"#)
        #expect(inside?.agentID == "a1")
        #expect(parse(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"true"}}"#)?.agentID == nil)
        #expect(parse(#"{"hook_event_name":"PreToolUse","session_id":"s","agent_id":"","tool_name":"Bash"}"#)?.agentID == nil)
    }
}
