import Foundation
@testable import PetCore
import Testing

struct InterruptTests {
    func line(_ json: String) -> Data { Data(json.utf8) }
    let prompt = #"{"type":"user","message":{"role":"user","content":"fix the build"}}"#
    let answer = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}"#
    let stop = #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    let stopInTool = #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    let meta = #"{"type":"last-prompt","lastPrompt":"x"}"#

    @Test func theLastExchangeDecides() {
        #expect(PermissionPrompt.endsInterrupted([prompt, stop].map(line)))
        #expect(PermissionPrompt.endsInterrupted([prompt, stopInTool, meta, meta].map(line)))
        // Answered, or asked again after the interrupt: not interrupted.
        #expect(!PermissionPrompt.endsInterrupted([prompt, answer].map(line)))
        #expect(!PermissionPrompt.endsInterrupted([prompt, stop, prompt].map(line)))
        #expect(!PermissionPrompt.endsInterrupted([line(meta), Data("garbage".utf8)]))
        #expect(!PermissionPrompt.endsInterrupted([]))
    }

    @Test func sessionsRememberTheirTranscript() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "UserPromptSubmit", "session_id": "s", "transcript_path": "/u/.claude/projects/p/s.jsonl"])
        let event = try #require(AgentEvent.parse(data))
        #expect(event.transcriptPath == "/u/.claude/projects/p/s.jsonl")
        var r = SessionRegistry()
        r.apply(event, at: Date())
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .stopped), at: Date())
        #expect(r.sessions["s"]?.transcriptPath == "/u/.claude/projects/p/s.jsonl")
        let odd = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "UserPromptSubmit", "session_id": "s", "transcript_path": "relative.txt"])
        #expect(AgentEvent.parse(odd)?.transcriptPath == nil)
    }

    /// The interrupt event a quiet session gets: idle at once, subagents dropped.
    @Test func anInterruptEndsTheTurn() {
        var r = SessionRegistry()
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .promptSubmitted), at: Date())
        r.apply(AgentEvent(sessionID: "s", cwd: nil, kind: .interrupted), at: Date())
        #expect(r.sessions["s"]?.status == .idle)
    }
}
