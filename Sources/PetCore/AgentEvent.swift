import Foundation

/// One Claude Code hook call, reduced to what the pet cares about. Prompt text and tool inputs are dropped here.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sessionStart(model: String?)
        case promptSubmitted
        case toolStarted(name: String, useID: String?)
        /// The turn is about to end with a question for the user (Claude desktop's next-step box with an `ask`).
        case questionAsked
        case toolFinished(name: String, useID: String?)
        case permissionRequested
        case notification(type: String?)
        case stopped
        /// The user cut the turn short (Codex `turn_aborted`): back to idle, nothing to celebrate.
        case interrupted
        /// Something happened inside a turn that is still running (Codex): keeps or puts it back to working.
        case stillWorking
        case failed
        case subagentStarted(id: String)
        case subagentStopped(id: String)
        case sessionEnded
        /// The context is about to be compacted (Claude Code `PreCompact`, Codex `compacted`).
        case compacting
    }

    public let sessionID: String
    public let cwd: String?
    public let kind: Kind

    public init(sessionID: String, cwd: String?, kind: Kind) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.kind = kind
    }

    /// Parses a raw hook payload; nil for events the pet ignores or malformed input.
    public static func parse(_ data: Data) -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["hook_event_name"] as? String,
              let session = json["session_id"] as? String, !session.isEmpty
        else { return nil }
        let tool = json["tool_name"] as? String ?? "?"
        let useID = json["tool_use_id"] as? String
        let kind: Kind
        switch name {
        case "SessionStart": kind = .sessionStart(model: json["model"] as? String)
        case "UserPromptSubmit": kind = .promptSubmitted
        case "PreToolUse":
            kind = asksUser(tool, json["tool_input"]) ? .questionAsked : .toolStarted(name: tool, useID: useID)
        case "PostToolUse", "PostToolUseFailure": kind = .toolFinished(name: tool, useID: useID)
        case "PermissionRequest": kind = .permissionRequested
        case "Notification": kind = .notification(type: json["notification_type"] as? String)
        case "Stop": kind = .stopped
        case "StopFailure": kind = .failed
        case "SubagentStart":
            guard let id = json["agent_id"] as? String else { return nil }
            kind = .subagentStarted(id: id)
        case "SubagentStop":
            guard let id = json["agent_id"] as? String else { return nil }
            kind = .subagentStopped(id: id)
        case "SessionEnd": kind = .sessionEnded
        case "PreCompact": kind = .compacting
        default: return nil
        }
        return AgentEvent(sessionID: session, cwd: json["cwd"] as? String, kind: kind)
    }

    /// The desktop app ends a turn that needs the user's decision with a wrap-up call carrying a non-empty `ask`.
    private static func asksUser(_ tool: String, _ input: Any?) -> Bool {
        guard tool.hasSuffix("__wrap_up"), let ask = (input as? [String: Any])?["ask"] as? String else { return false }
        return !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One line for the opt-in event log: ids, project and event names only, never prompts or tool input.
    public var logLine: String {
        let project = AgentSession.projectName(for: cwd) ?? "-"
        let detail: String
        switch kind {
        case .sessionStart(let model): detail = "sessionStart \(model ?? "-")"
        case .promptSubmitted: detail = "promptSubmitted"
        case .toolStarted(let name, _): detail = "toolStarted \(name)"
        case .questionAsked: detail = "questionAsked"
        case .toolFinished(let name, _): detail = "toolFinished \(name)"
        case .permissionRequested: detail = "permissionRequested"
        case .notification(let type): detail = "notification \(type ?? "-")"
        case .stopped: detail = "stopped"
        case .interrupted: detail = "interrupted"
        case .stillWorking: detail = "stillWorking"
        case .failed: detail = "failed"
        case .subagentStarted: detail = "subagentStarted"
        case .subagentStopped: detail = "subagentStopped"
        case .sessionEnded: detail = "sessionEnded"
        case .compacting: detail = "compacting"
        }
        return "\(sessionID.prefix(8)) \(project) \(detail)"
    }
}
