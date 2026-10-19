import Foundation

/// What an agent is doing right now, for the icon in the bubble over the keyboard.
public enum ToolKind: Sendable, Equatable {
    case run, search, read, edit

    /// Claude Code's built-in tools; anything else (subagents, todos, MCP tools) shows no icon.
    public init?(toolName: String) {
        switch toolName {
        case "Bash", "BashOutput": self = .run
        case "Grep", "Glob", "WebSearch", "LS": self = .search
        case "Read", "WebFetch", "NotebookRead": self = .read
        case "Edit", "MultiEdit", "Write", "NotebookEdit": self = .edit
        default: return nil
        }
    }

    /// The tool of the working session heard from last, if it is one with an icon.
    public static func current(in sessions: [AgentSession]) -> ToolKind? {
        sessions.filter { $0.status == .working && $0.currentTool != nil }
            .max { $0.lastEventAt < $1.lastEventAt }
            .flatMap { $0.currentTool.flatMap(ToolKind.init(toolName:)) }
    }
}
