import Foundation

/// Adds and removes the pet's hook entries in Claude Code's settings JSON without touching anything else.
public enum HookSettings {
    public enum Error: Swift.Error, Equatable {
        /// A hooks value we don't understand; we refuse rather than risk dropping the user's data.
        case unexpectedShape(String)
    }

    /// Checked against the event names in Claude Code 2.1.299's binary (see docs/spike-notes.md).
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
        "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd",
    ]

    public static func isInstalled(in settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ((hooks[$0] as? [[String: Any]]) ?? []).contains { ours($0, command) } }
    }

    public static func install(into settings: [String: Any], command: String) throws -> [String: Any] {
        var out = settings
        var hooks = try hooksDict(settings)
        for event in events {
            var list = try groups(hooks[event], event)
            if !list.contains(where: { ours($0, command) }) {
                list.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
            }
            hooks[event] = list
        }
        out["hooks"] = hooks
        return out
    }

    public static func uninstall(from settings: [String: Any], command: String) throws -> [String: Any] {
        var out = settings
        guard settings["hooks"] != nil else { return out }
        var hooks = try hooksDict(settings)
        for event in hooks.keys {
            let list = try groups(hooks[event], event)
            guard list.contains(where: { ours($0, command) }) else { continue }
            let kept = list.compactMap { group -> [String: Any]? in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = entries.filter { $0["command"] as? String != command }
                if remaining.isEmpty { return nil }
                var g = group
                g["hooks"] = remaining
                return g
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        out["hooks"] = hooks.isEmpty ? nil : hooks
        return out
    }

    public enum StatusLineState: Equatable, Sendable { case ours, foreign, absent }

    public static func statusLineState(in settings: [String: Any], command: String) -> StatusLineState {
        guard let line = settings["statusLine"] else { return .absent }
        return (line as? [String: Any])?["command"] as? String == command ? .ours : .foreign
    }

    /// Takes the statusline only when the user has none; someone else's statusline is left untouched.
    public static func installStatusLine(into settings: [String: Any], command: String) -> ([String: Any], StatusLineState) {
        let state = statusLineState(in: settings, command: command)
        guard state == .absent else { return (settings, state) }
        var out = settings
        out["statusLine"] = ["type": "command", "command": command]
        return (out, .ours)
    }

    public static func uninstallStatusLine(from settings: [String: Any], command: String) -> [String: Any] {
        guard statusLineState(in: settings, command: command) == .ours else { return settings }
        var out = settings
        out.removeValue(forKey: "statusLine")
        return out
    }

    private static func hooksDict(_ settings: [String: Any]) throws -> [String: Any] {
        guard let value = settings["hooks"] else { return [:] }
        guard let dict = value as? [String: Any] else { throw Error.unexpectedShape("hooks") }
        return dict
    }

    private static func groups(_ value: Any?, _ event: String) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let list = value as? [[String: Any]] else { throw Error.unexpectedShape("hooks.\(event)") }
        return list
    }

    private static func ours(_ group: [String: Any], _ command: String) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
    }
}

/// Installs the hook script and wires it into ~/.claude/settings.json, with a timestamped backup first.
public struct HookInstaller: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidSettings(String)
    }

    public let settingsURL: URL
    public let scriptURL: URL
    public var statusLineScriptURL: URL { scriptURL.deletingLastPathComponent().appendingPathComponent("pixelpet-statusline") }

    public static let script = """
    #!/bin/sh
    # Pixel Pet hook: forwards the hook JSON to the pet over a unix socket.
    # Never blocks or fails Claude Code: no output, always exit 0, stdin always drained.
    if [ -n "${PIXELPET_INTERNAL:-}" ]; then
        cat >/dev/null
        exit 0
    fi
    SOCK="$HOME/.pixelpet/pet.sock"
    if [ -S "$SOCK" ]; then
        nc -U -w 1 "$SOCK" >/dev/null 2>&1 || cat >/dev/null
    else
        cat >/dev/null
    fi
    exit 0

    """

    /// Statusline for terminal sessions: shares the snapshot with the pet and prints a compact line.
    /// `plutil` reads JSON from stdin, so this needs nothing beyond the base system.
    public static let statusLineScript = """
    #!/bin/sh
    # Pixel Pet statusline: forwards Claude Code's statusline JSON to the pet and prints
    # "Model · ctx N% · 5h N% · 7d N%". Never fails; missing fields are skipped.
    # C locale: printf must read "42.4" the same way under a comma-decimal terminal locale.
    export LC_ALL=C
    input=$(cat)
    SOCK="$HOME/.pixelpet/pet.sock"
    if [ -S "$SOCK" ]; then
        printf '%s' "$input" | nc -U -w 1 "$SOCK" >/dev/null 2>&1
    fi
    get() { printf '%s' "$input" | plutil -extract "$1" raw -o - - 2>/dev/null; }
    pct() { [ -n "$1" ] && printf '%.0f' "$1" 2>/dev/null; }
    model=$(get model.display_name)
    line="${model:-Claude}"
    ctx=$(pct "$(get context_window.used_percentage)") && line="$line · ctx $ctx%"
    five=$(pct "$(get rate_limits.five_hour.used_percentage)") && line="$line · 5h $five%"
    week=$(pct "$(get rate_limits.seven_day.used_percentage)") && line="$line · 7d $week%"
    printf '%s\\n' "$line"
    exit 0

    """

    public init(settingsURL: URL = HookInstaller.defaultSettingsURL, scriptURL: URL = HookInstaller.defaultScriptURL) {
        self.settingsURL = settingsURL
        self.scriptURL = scriptURL
    }

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelpet/bin/pixelpet-hook")
    }

    /// Hook commands run through a shell, so the path is single-quoted to survive spaces.
    public static func command(for script: URL) -> String {
        "'" + script.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private var command: String { Self.command(for: scriptURL) }
    private var statusLineCommand: String { Self.command(for: statusLineScriptURL) }

    public var statusLineState: HookSettings.StatusLineState {
        guard let settings = try? readSettings() else { return .absent }
        return HookSettings.statusLineState(in: settings, command: statusLineCommand)
    }

    public var isInstalled: Bool {
        guard let settings = try? readSettings() else { return false }
        return FileManager.default.isExecutableFile(atPath: scriptURL.path)
            && HookSettings.isInstalled(in: settings, command: command)
    }

    public func install() throws {
        let settings = try readSettings()
        let withHooks = try HookSettings.install(into: settings, command: command)
        let (updated, _) = HookSettings.installStatusLine(into: withHooks, command: statusLineCommand)
        try writeScripts()
        try writeSettings(updated, original: settings)
    }

    public func uninstall() throws {
        let settings = try readSettings()
        let withoutHooks = try HookSettings.uninstall(from: settings, command: command)
        try writeSettings(HookSettings.uninstallStatusLine(from: withoutHooks, command: statusLineCommand), original: settings)
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: statusLineScriptURL)
    }

    /// Adds only the statusline to an existing connection; a user's own statusline is left alone.
    public func installStatusLine() throws {
        let settings = try readSettings()
        let (updated, _) = HookSettings.installStatusLine(into: settings, command: statusLineCommand)
        try writeScripts()
        try writeSettings(updated, original: settings)
    }

    /// Keeps an already-connected hook script in sync with this build of the app.
    public func refreshScriptIfInstalled() throws {
        guard let settings = try? readSettings(), HookSettings.isInstalled(in: settings, command: command) else { return }
        let hook = try? String(contentsOf: scriptURL, encoding: .utf8)
        let line = try? String(contentsOf: statusLineScriptURL, encoding: .utf8)
        if hook != Self.script || line != Self.statusLineScript { try writeScripts() }
    }

    private func writeScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        for (url, text) in [(scriptURL, Self.script), (statusLineScriptURL, Self.statusLineScript)] {
            try Data(text.utf8).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// Missing or empty file means "no settings yet"; any other read problem is an error, never an empty object.
    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidSettings(settingsURL.path)
        }
        return json
    }

    /// Writes through symlinks, keeps the file's permissions, backs it up first, and skips no-op writes.
    private func writeSettings(_ settings: [String: Any], original: [String: Any]) throws {
        guard !NSDictionary(dictionary: settings).isEqual(to: original) else { return }
        let fm = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var permissions: Any?
        if fm.fileExists(atPath: target.path) {
            permissions = try fm.attributesOfItem(atPath: target.path)[.posixPermissions]
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("\(settingsURL.lastPathComponent).pixelpet-backup-\(stamp)")
            try fm.copyItem(at: target, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
    }
}
