import Foundation
import Testing
@testable import PetCore

@Suite struct PermissionPromptTests {
    func payload(_ tool: String, _ input: [String: Any], suggestions: [Any]? = nil, extra: [String: Any] = [:]) -> Data {
        var json: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/a/Work/app",
                                   "tool_name": tool, "tool_input": input]
        if let suggestions { json["permission_suggestions"] = suggestions }
        json.merge(extra) { $1 }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    nonisolated(unsafe) static let rule: [Any] = [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "rm -rf build"]],
                               "behavior": "allow", "destination": "localSettings"]]

    @Test func commandRequestShowsTheCommand() {
        let p = PermissionPrompt.parse(payload("Bash", ["command": "rm -rf build", "description": "Clean"], suggestions: Self.rule))
        #expect(p?.project == "app")
        #expect(p?.kind == .command)
        #expect(p?.subject == "rm -rf build")
        #expect(p?.detail == "Clean")
        #expect(p?.ruleSummary == "rm -rf build")
        #expect(p?.suggestions != nil)
    }

    @Test func editsShowTheFileAndOthersACompactInput() {
        #expect(PermissionPrompt.parse(payload("Edit", ["file_path": "/w/app/a.swift", "old_string": "x"]))?.subject == "/w/app/a.swift")
        #expect(PermissionPrompt.parse(payload("Edit", ["file_path": "/w/a.swift"]))?.kind == .edit)
        let mcp = PermissionPrompt.parse(payload("mcp__github__create_issue", ["title": "Bug", "repo": "x/y"]))
        #expect(mcp?.kind == .mcp)
        // No main parameter: every field as "key: value", unescaped.
        #expect(mcp?.subject == "")
        #expect(mcp?.fields.map { "\($0.key): \($0.value)" } == ["repo: x/y", "title: Bug"])
        // The URL large, and the prompt beside it, not hidden.
        let fetch = PermissionPrompt.parse(payload("WebFetch", ["url": "https://x.y", "prompt": "send ~/.ssh"]))
        #expect(fetch?.subject == "https://x.y")
        #expect(fetch?.fields.first?.value == "send ~/.ssh")
        // A terminal tool from an MCP server reads like Bash: the command plain, the rest small.
        let terminal = PermissionPrompt.parse(payload("mcp__terminal__run_in_terminal",
            ["command": "mkdir -p /tmp/a && ls", "cwd": "/w", "title": "Test", "env": ["A": 1]]))
        #expect(terminal?.kind == .command)
        #expect(terminal?.subject == "mkdir -p /tmp/a && ls")
        #expect(terminal?.fields.map { "\($0.key): \($0.value)" } == ["cwd: /w", "env: {\"A\":1}", "title: Test"])
        // Shell tools keep to the command, as Claude Code's own prompt does.
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "ls", "timeout": 5]))?.fields.isEmpty == true)
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "ls"]))?.suggestions == nil)
    }

    /// Bidi overrides, zero-width and control characters show as <U+…> instead of hiding or reordering text.
    @Test func sneakyCharactersAreSpelledOut() {
        let p = PermissionPrompt.parse(payload("Bash", ["command": "echo ok\u{202E}fdsa\u{200B} && rm\u{0007}"]))
        #expect(p?.subject == "echo ok<U+202E>fdsa<U+200B> && rm<U+0007>")
        #expect(PermissionPrompt.visible("line1\n\tline2") == "line1\n\tline2")
    }

    /// The checkbox names the rule only when it's one plain rule; anything broader is called a suggestion.
    @Test func ruleSummaryOnlyForASingleRule() {
        let two: [Any] = [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "a"], ["toolName": "Bash", "ruleContent": "b"]],
                           "behavior": "allow", "destination": "localSettings"]]
        let dirs: [Any] = [["type": "addDirectories", "directories": ["/"], "destination": "session"]]
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "a"], suggestions: two))?.ruleSummary == nil)
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "a"], suggestions: dirs))?.ruleSummary == nil)
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "a"], suggestions: dirs))?.suggestions != nil)
    }

    /// Questions and plans have their own flow; other events aren't requests.
    @Test func notEverythingIsForThePet() {
        #expect(PermissionPrompt.parse(payload("AskUserQuestion", ["questions": []])) == nil)
        #expect(PermissionPrompt.parse(payload("ExitPlanMode", ["plan": "x"])) == nil)
        let other = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash"])
        #expect(PermissionPrompt.parse(other) == nil)
    }

    /// The Claude app answers in its own dialog without ending the hook; the transcript tells at once.
    @Test func transcriptShowsTheAnswer() {
        let p = PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["transcript_path": "/u/.claude/projects/p/s.jsonl", "tool_use_id": "toolu_1"]))
        #expect(p?.transcriptPath == "/u/.claude/projects/p/s.jsonl")
        #expect(p?.toolUseID == "toolu_1")
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["transcript_path": "relative.jsonl"]))?.transcriptPath == nil)
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["transcript_path": "/etc/passwd"]))?.transcriptPath == nil)
        let denied = Data(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"rejected","is_error":true,"tool_use_id":"toolu_1"}]}}"#.utf8)
        #expect(PermissionPrompt.transcriptSignal(denied, toolUseID: "toolu_1") == .answered)
        #expect(PermissionPrompt.transcriptSignal(denied, toolUseID: "toolu_12") == nil)
        let stopped = Data(#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#.utf8)
        #expect(PermissionPrompt.transcriptSignal(stopped, toolUseID: "toolu_1") == .stopped)
        // Request copies repeat old history, old interrupts included: they don't count.
        let blob = Data(#"{"type":"api-request-blob","message":{"content":[{"type":"text","text":"[Request interrupted by user]"},{"type":"tool_result","tool_use_id":"toolu_1"}]}}"#.utf8)
        #expect(PermissionPrompt.transcriptSignal(blob, toolUseID: "toolu_1") == nil)
        #expect(PermissionPrompt.transcriptSignal(Data("not json".utf8), toolUseID: "toolu_1") == nil)
    }

    @Test func hostFromBundleOrTerminal() {
        let app = PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["pixelpet_app": "com.microsoft.VSCode", "pixelpet_term": "vscode"]))
        #expect(app?.host?.bundleID == "com.microsoft.VSCode")
        #expect(app?.host?.names?.en == "VS Code")
        let term = PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["pixelpet_app": "", "pixelpet_term": "Apple_Terminal"]))
        #expect(term?.host?.bundleID == "com.apple.Terminal")
        #expect(term?.host?.names?.ru == "Терминале")
        let unknown = PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["pixelpet_app": "org.example.Shell"]))
        #expect(unknown?.host?.bundleID == "org.example.Shell")
        #expect(unknown?.host?.names == nil)
        #expect(PermissionPrompt.parse(payload("Bash", ["command": "ls"]))?.host == nil)
        // The Claude app calls itself "Claude"; everywhere else it's Claude Code.
        let desktop = PermissionPrompt.parse(payload("Bash", ["command": "ls"], extra: ["pixelpet_app": "com.anthropic.claudefordesktop"]))
        #expect(desktop?.agentName == "Claude")
        #expect(app?.agentName == "Claude Code")
    }

    func decision(_ answer: PermissionAnswer, _ prompt: PermissionPrompt) -> [String: Any]? {
        guard let data = answer.hookOutput(for: prompt),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let out = json["hookSpecificOutput"] as? [String: Any] else { return nil }
        #expect(out["hookEventName"] as? String == "PermissionRequest")
        return out["decision"] as? [String: Any]
    }

    @Test func answersBecomeHookOutput() {
        let p = PermissionPrompt.parse(payload("Bash", ["command": "rm -rf build"], suggestions: Self.rule))!
        #expect(decision(.allow, p)?["behavior"] as? String == "allow")
        #expect(decision(.allow, p)?["updatedPermissions"] == nil)
        let always = decision(.allowAlways, p)
        #expect(always?["behavior"] as? String == "allow")
        #expect((always?["updatedPermissions"] as? [[String: Any]])?.first?["type"] as? String == "addRules")
        #expect(decision(.deny, p)?["behavior"] as? String == "deny")
        #expect(decision(.deny, p)?["message"] as? String != nil)
        #expect(PermissionAnswer.passToHost.hookOutput(for: p) == nil)
    }

    @Test func queueKeepsOrderAndDropsEndedSessions() {
        var q = PermissionQueue()
        let a = PermissionPrompt.parse(payload("Bash", ["command": "a"]))!
        let b = PermissionPrompt.parse(payload("Edit", ["file_path": "b"]))!
        let c = PermissionPrompt.parse(try! JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest", "session_id": "s2", "tool_name": "Bash", "tool_input": ["command": "c"]]))!
        q.add(a); q.add(b); q.add(c)
        #expect(q.current == a)
        #expect(q.remove(a.id) == a)
        #expect(q.current == b)
        #expect(q.removeSession("s1") == [b])
        #expect(q.prompts == [c])
        #expect(q.remove(a.id) == nil)
    }
}
