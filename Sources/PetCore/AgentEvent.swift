import Foundation

/// One Claude Code hook call, reduced to what the pet cares about. Prompt text and tool inputs are dropped here.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sessionStart(model: String?)
        case promptSubmitted
        case toolStarted(name: String, useID: String?)
        case toolFinished(name: String, useID: String?)
        case permissionRequested
        case notification(type: String?)
        case stopped
        case failed
        case subagentStarted(id: String)
        case subagentStopped(id: String)
        case sessionEnded
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
        case "PreToolUse": kind = .toolStarted(name: tool, useID: useID)
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
        default: return nil
        }
        return AgentEvent(sessionID: session, cwd: json["cwd"] as? String, kind: kind)
    }
}
