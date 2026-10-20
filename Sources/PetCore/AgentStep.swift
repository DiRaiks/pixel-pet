import Foundation

/// What an agent is doing in one tool call, in a few words: the action and what it acts on. Built from the
/// tool input when the call starts; the rest of the input is dropped, and this is kept in memory only.
public struct AgentStep: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case run, read, edit, write, search, findFiles, fetch, webSearch, subagent
        /// Any other tool, by its name (MCP tools too).
        case tool(String)
    }

    public let action: Action
    /// The command's first line, a file name, a pattern, a host or a query; nil when there's nothing short to show.
    public let object: String?

    public init(action: Action, object: String?) {
        self.action = action
        self.object = object
    }

    static let maxObject = 60

    public static func describe(tool: String, input: [String: Any]) -> AgentStep {
        func string(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let fileName = { (key: String) in string(key).map { ($0 as NSString).lastPathComponent } }
        let (action, object): (Action, String?) = switch tool {
        case "Bash": (.run, string("command").flatMap(firstLine).map(dropLeadingCd))
        case "Read": (.read, fileName("file_path"))
        case "Edit", "MultiEdit": (.edit, fileName("file_path"))
        case "NotebookEdit": (.edit, fileName("notebook_path"))
        case "Write": (.write, fileName("file_path"))
        case "Grep": (.search, string("pattern"))
        case "Glob": (.findFiles, string("pattern"))
        case "WebFetch": (.fetch, string("url").flatMap { URL(string: $0)?.host })
        case "WebSearch": (.webSearch, string("query"))
        case "Task", "Agent": (.subagent, string("description"))
        default: (.tool(tool), nil)
        }
        return AgentStep(action: action, object: object.flatMap(short))
    }

    /// `cd dir && make` reads as `make`: the directory says little, and the command would be cut off.
    static func dropLeadingCd(_ line: String) -> String {
        let rest = line.replacingOccurrences(of: #"^\s*cd\s+("[^"]*"|'[^']*'|\S+)\s*(&&|;)\s*"#, with: "", options: .regularExpression)
        return rest.isEmpty ? line : rest
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    /// Trimmed, cut to `maxObject` characters, and with hidden or reordering characters spelled out.
    static func short(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let cut = trimmed.count > maxObject ? String(trimmed.prefix(maxObject - 1)) + "…" : trimmed
        return PermissionPrompt.visible(cut)
    }
}
