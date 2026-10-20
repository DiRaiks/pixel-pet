import Foundation

/// A Claude Code permission request the pet can answer itself (the hook waits on the socket for it).
/// What it shows is read from the request when it arrives and kept only while the card is open; it's
/// never stored or logged.
public struct PermissionPrompt: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let project: String?
    public let tool: String
    /// What the tool would act on, shown large: the command, the file, the URL, the query.
    public let subject: String
    /// The rest of the input as "key: value" lines, so nothing hides; empty for shell and edit tools, whose
    /// other parameters (timeouts, old and new strings) Claude Code's own prompt doesn't show either.
    public let fields: [(key: String, value: String)]
    /// The main parameter is a shell command, whatever the tool (an MCP terminal, say).
    let runsCommand: Bool

    public static func == (a: PermissionPrompt, b: PermissionPrompt) -> Bool { a.id == b.id }
    /// The model's own one-line description of the call, when it gives one.
    public let detail: String?
    /// Claude Code's suggested rule for "don't ask again" (raw permission updates, sent back as they are).
    public let suggestions: Data?
    /// What the rule covers, for the checkbox ("rm -rf build", "Edit"); nil when the suggestion is more than
    /// one plain rule, and the checkbox then says so instead of naming just part of it.
    public let ruleSummary: String?
    /// Where the session runs (`__CFBundleIdentifier`, `TERM_PROGRAM` of the Claude Code process).
    public let host: AgentHost?
    /// The session's transcript: answering in Claude Code writes the call's result there at once, while the
    /// Claude app keeps the hook running for up to a minute after its own dialog was answered.
    public let transcriptPath: String?
    /// The call asked about, when the hook says (otherwise the session's last `PreToolUse` of this tool).
    public let toolUseID: String?

    /// Tools that ask the user something rather than for permission; they keep their own flow.
    static let notForThePet: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    public static func parse(_ data: Data, id: UUID = UUID()) -> PermissionPrompt? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["hook_event_name"] as? String == "PermissionRequest",
              let session = json["session_id"] as? String, !session.isEmpty,
              let tool = json["tool_name"] as? String, !notForThePet.contains(tool)
        else { return nil }
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let suggestions = (json["permission_suggestions"] as? [Any]).flatMap { $0.isEmpty ? nil : $0 }
        let main = mainKey(tool, input)
        let quiet = ["Bash", "Edit", "MultiEdit", "Write", "NotebookEdit"].contains(tool)
        return PermissionPrompt(
            id: id, sessionID: session, project: AgentSession.projectName(for: json["cwd"] as? String), tool: tool,
            subject: main.flatMap { input[$0].map(text) }.map(visible) ?? (input.isEmpty ? tool : ""),
            fields: quiet ? [] : input.keys.sorted().filter { $0 != main && $0 != "description" }
                .map { (key: $0, value: visible(text(input[$0]!))) },
            runsCommand: main == "command",
            detail: (input["description"] as? String).flatMap { $0.isEmpty ? nil : visible($0) },
            suggestions: suggestions.flatMap { try? JSONSerialization.data(withJSONObject: $0) },
            ruleSummary: suggestions.flatMap(ruleSummary),
            host: AgentHost(bundleID: json["pixelpet_app"] as? String, term: json["pixelpet_term"] as? String),
            transcriptPath: (json["transcript_path"] as? String).flatMap { $0.hasPrefix("/") && $0.hasSuffix(".jsonl") ? $0 : nil },
            toolUseID: (json["tool_use_id"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    public enum TranscriptSignal: Equatable, Sendable {
        /// The call has its result: allowed and run, or denied.
        case answered
        /// The turn was stopped (a denial in Claude Code stops it, and no hook reports that).
        case stopped
    }

    /// What one transcript line says about the request. Only the session's own `user` entries count: the
    /// request copies (`api-request-blob`) repeat old history, interrupts included.
    public static func transcriptSignal(_ line: Data, toolUseID: String) -> TranscriptSignal? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any], json["type"] as? String == "user",
              let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return nil }
        if content.contains(where: { ($0["text"] as? String)?.hasPrefix("[Request interrupted by user") == true }) {
            return .stopped
        }
        return content.contains { $0["type"] as? String == "tool_result" && $0["tool_use_id"] as? String == toolUseID }
            ? .answered : nil
    }

    /// The parameter built-in tools act on.
    static let builtInKey: [String: String] = [
        "Bash": "command", "BashOutput": "bash_id", "KillShell": "shell_id", "Edit": "file_path", "MultiEdit": "file_path",
        "Write": "file_path", "NotebookEdit": "notebook_path", "WebFetch": "url", "WebSearch": "query",
    ]

    /// The parameter to show large: the built-in one, or for other tools the first of these they have.
    static func mainKey(_ tool: String, _ input: [String: Any]) -> String? {
        if let key = builtInKey[tool], input[key] != nil { return key }
        return ["command", "file_path", "path", "url", "query", "pattern"].first { input[$0] is String }
    }

    /// Strings as they are; anything else as compact JSON, with "/" left alone.
    static func text(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return text
    }

    /// Text that could hide or reorder what's shown (bidi overrides, zero-width and control characters other
    /// than newlines and tabs) is spelled out as <U+202E> instead of taking effect.
    public static func visible(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let sneaky = (v < 0x20 && v != 0x0A && v != 0x09) || v == 0x7F || (0x200B...0x200F).contains(v)
                || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) || v == 0xFEFF
            out += sneaky ? String(format: "<U+%04X>", v) : String(scalar)
        }
        return out
    }

    /// "rm -rf build" for a single command rule, the tool name for a single tool-wide one; nil for anything
    /// broader (several rules, directories, a mode change), which the checkbox then calls Claude Code's
    /// suggestion as a whole.
    static func ruleSummary(_ suggestions: [Any]) -> String? {
        guard suggestions.count == 1, let entry = suggestions.first as? [String: Any],
              entry["type"] as? String == "addRules", let rules = entry["rules"] as? [Any], rules.count == 1,
              let rule = rules.first as? [String: Any] else { return nil }
        if let content = rule["ruleContent"] as? String, !content.isEmpty { return visible(content) }
        return rule["toolName"] as? String
    }

    /// What kind of thing is asked, for the card's title.
    public var kind: Kind {
        if runsCommand { return .command }
        return switch tool {
        case "Bash", "BashOutput", "KillShell": .command
        case "Edit", "MultiEdit", "Write", "NotebookEdit": .edit
        case "WebFetch", "WebSearch": .web
        default: tool.hasPrefix("mcp__") ? .mcp : .other
        }
    }

    public enum Kind: Sendable { case command, edit, web, mcp, other }

    /// "Claude" for a session in the Claude app, "Claude Code" elsewhere (terminal, editors).
    public var agentName: String { host?.bundleID == "com.anthropic.claudefordesktop" ? "Claude" : "Claude Code" }
}

/// The pet's answer, as the hook prints it for Claude Code.
public enum PermissionAnswer: Equatable, Sendable {
    case allow
    /// Allow and add Claude Code's suggested rule, like "Yes, don't ask again" in the terminal.
    case allowAlways
    case deny
    /// Let Claude Code ask the usual way, where the session runs.
    case passToHost

    /// The hook's stdout; nil prints nothing, which leaves Claude Code's own prompt.
    public func hookOutput(for prompt: PermissionPrompt) -> Data? {
        var decision: [String: Any]
        switch self {
        case .passToHost: return nil
        case .allow: decision = ["behavior": "allow"]
        case .allowAlways:
            decision = ["behavior": "allow"]
            if let raw = prompt.suggestions, let rules = try? JSONSerialization.jsonObject(with: raw) {
                decision["updatedPermissions"] = rules
            }
        case .deny: decision = ["behavior": "deny", "message": "Denied from Pixel Pet."]
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    }
}

/// Requests waiting for an answer, oldest first: the card shows one at a time with "1 of N".
public struct PermissionQueue: Sendable {
    public private(set) var prompts: [PermissionPrompt] = []

    public init() {}

    public var current: PermissionPrompt? { prompts.first }

    public mutating func add(_ prompt: PermissionPrompt) { prompts.append(prompt) }

    /// Answered, timed out, or the hook went away: drop it.
    @discardableResult
    public mutating func remove(_ id: UUID) -> PermissionPrompt? {
        guard let i = prompts.firstIndex(where: { $0.id == id }) else { return nil }
        return prompts.remove(at: i)
    }

    /// A session that ended can't be answered any more.
    public mutating func removeSession(_ sessionID: String) -> [PermissionPrompt] {
        let gone = prompts.filter { $0.sessionID == sessionID }
        prompts.removeAll { $0.sessionID == sessionID }
        return gone
    }
}

/// The app a Claude Code session runs in, from its process environment, for "Answer in …".
public struct AgentHost: Equatable, Sendable {
    public let bundleID: String?
    public let names: (en: String, ru: String)?

    public static func == (a: AgentHost, b: AgentHost) -> Bool { a.bundleID == b.bundleID && a.names?.en == b.names?.en }

    init?(bundleID: String?, term: String?) {
        let bundle = bundleID.flatMap { $0.isEmpty ? nil : $0 } ?? term.flatMap { Self.terms[$0] }
        guard let bundle else { return nil }
        self.bundleID = bundle
        names = Self.known[bundle]
    }

    /// `TERM_PROGRAM` values, for shells that don't pass the bundle id on.
    static let terms: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2", "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable", "vscode": "com.microsoft.VSCode", "WezTerm": "com.github.wez.wezterm",
    ]

    /// Names in "Answer in …" (Russian in the prepositional case).
    static let known: [String: (en: String, ru: String)] = [
        "com.apple.Terminal": ("Terminal", "Терминале"), "com.googlecode.iterm2": ("iTerm", "iTerm"),
        "com.mitchellh.ghostty": ("Ghostty", "Ghostty"), "dev.warp.Warp-Stable": ("Warp", "Warp"),
        "com.github.wez.wezterm": ("WezTerm", "WezTerm"), "com.microsoft.VSCode": ("VS Code", "VS Code"),
        "com.todesktop.230313mzl4w4u92": ("Cursor", "Cursor"), "dev.zed.Zed": ("Zed", "Zed"),
        "com.anthropic.claudefordesktop": ("Claude", "Claude"), "com.exafunction.windsurf": ("Windsurf", "Windsurf"),
    ]
}

/// How long a permission request waits for the pet, at each layer: the pet lets go first, then the hook's
/// `nc`, then Claude Code's timeout for the hook, so it never cuts off an answer in flight.
public enum PermissionWait {
    public static let window: TimeInterval = 60
    public static let ncTimeout = 70
    public static let hookTimeout = 75
}
