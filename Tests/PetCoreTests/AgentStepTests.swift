import Foundation
@testable import PetCore
import Testing

struct AgentStepTests {
    func step(_ tool: String, _ input: [String: Any]) -> AgentStep { AgentStep.describe(tool: tool, input: input) }

    @Test func eachToolSaysWhatAndOnWhat() {
        #expect(step("Bash", ["command": "npm test\necho done"]) == AgentStep(action: .run, object: "npm test"))
        #expect(step("Read", ["file_path": "/w/app/README.md"]) == AgentStep(action: .read, object: "README.md"))
        #expect(step("Edit", ["file_path": "/w/App.swift", "old_string": "secret"]) == AgentStep(action: .edit, object: "App.swift"))
        #expect(step("NotebookEdit", ["notebook_path": "/w/a.ipynb"]) == AgentStep(action: .edit, object: "a.ipynb"))
        #expect(step("Write", ["file_path": "/w/notes.md", "content": "x"]) == AgentStep(action: .write, object: "notes.md"))
        #expect(step("Grep", ["pattern": "onGone"]) == AgentStep(action: .search, object: "onGone"))
        #expect(step("Glob", ["pattern": "**/*.swift"]) == AgentStep(action: .findFiles, object: "**/*.swift"))
        #expect(step("WebFetch", ["url": "https://docs.swift.org/x?token=1", "prompt": "p"]) == AgentStep(action: .fetch, object: "docs.swift.org"))
        #expect(step("WebSearch", ["query": "swift kqueue"]) == AgentStep(action: .webSearch, object: "swift kqueue"))
        #expect(step("Task", ["description": "Explore hooks", "prompt": "long"]) == AgentStep(action: .subagent, object: "Explore hooks"))
        #expect(step("mcp__terminal__run", ["command": "ls"]) == AgentStep(action: .tool("mcp__terminal__run"), object: nil))
        #expect(step("Bash", [:]) == AgentStep(action: .run, object: nil))
        #expect(step("Bash", ["command": "cd ~/Work/app && swift build"]).object == "swift build")
        #expect(step("Bash", ["command": "cd \"/a b\"; make"]).object == "make")
        #expect(step("Bash", ["command": "cd /tmp"]).object == "cd /tmp")
    }

    @Test func objectsAreShortAndVisible() {
        let long = step("Bash", ["command": String(repeating: "a", count: 100)]).object
        #expect(long?.count == AgentStep.maxObject)
        #expect(long?.hasSuffix("…") == true)
        #expect(step("Grep", ["pattern": "a\u{202E}b"]).object == "a<U+202E>b")
        #expect(step("Bash", ["command": "   "]).object == nil)
    }

    @Test func onlyStartingCallsCarryAStep() {
        func event(_ name: String, _ tool: String) -> AgentEvent? {
            AgentEvent.parse(try! JSONSerialization.data(withJSONObject: [
                "hook_event_name": name, "session_id": "s", "tool_name": tool, "tool_input": ["command": "ls"]]))
        }
        #expect(event("PreToolUse", "Bash")?.step == AgentStep(action: .run, object: "ls"))
        #expect(event("PostToolUse", "Bash")?.step == nil)
    }
}
