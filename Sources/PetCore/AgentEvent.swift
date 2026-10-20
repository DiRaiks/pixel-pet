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
        /// The pet's card lost its request: answered in Claude Code itself, which reports neither allow nor deny.
        case permissionSettled
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
    /// A Bash call that ran `git push` and succeeded (the command itself is not kept).
    public let pushed: Bool
    /// For a tool call starting: what it does, in a few words (`AgentStep`); the rest of the input is dropped.
    public let step: AgentStep?
    /// The app the session runs in, from the hook script's tags.
    public let host: AgentHost?

    public init(sessionID: String, cwd: String?, kind: Kind, pushed: Bool = false, step: AgentStep? = nil, host: AgentHost? = nil) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.kind = kind
        self.pushed = pushed
        self.step = step
        self.host = host
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
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let pushed = name == "PostToolUse" && tool == "Bash" && isGitPush(input["command"] as? String)
        var step: AgentStep?
        if case .toolStarted = kind { step = AgentStep.describe(tool: tool, input: input) }
        let host = AgentHost(bundleID: json["pixelpet_app"] as? String, term: json["pixelpet_term"] as? String)
        return AgentEvent(sessionID: session, cwd: json["cwd"] as? String, kind: kind, pushed: pushed, step: step, host: host)
    }

    /// `git push` as a command in a shell line (also `git -C dir push`), not a dry run. Quoted text is
    /// blanked first, so a commit message or an echo that mentions "git push" doesn't count.
    static func isGitPush(_ command: String?) -> Bool {
        guard var line = command else { return false }
        line = line.replacingOccurrences(of: #""(\\.|[^"\\])*"|'[^']*'"#, with: "Q", options: .regularExpression)
        guard let push = line.range(of: #"(^|[\s;&|(])git(\s+-\S+(\s+[^\s-]\S*)?)*\s+push\b[^;&|\n]*"#,
                                    options: .regularExpression) else { return false }
        return line[push].range(of: #"\s(-n|--dry-run)\b"#, options: .regularExpression) == nil
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
        case .permissionSettled: detail = "permissionSettled"
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
