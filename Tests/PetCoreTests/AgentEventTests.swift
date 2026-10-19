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
        #expect(parse(#"{"hook_event_name":"PreCompact","session_id":"s"}"#) == nil)
        #expect(parse(#"{"hook_event_name":"Stop"}"#) == nil)
        #expect(parse("not json") == nil)
        #expect(parse(#"["array"]"#) == nil)
    }

    @Test func projectNameIsLastPathComponent() {
        #expect(AgentSession.projectName(for: "/Users/a/Work/pixel-pet") == "pixel-pet")
        #expect(AgentSession.projectName(for: nil) == nil)
    }
}
