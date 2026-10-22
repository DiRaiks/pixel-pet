import Foundation

/// Adds and removes the pet's hook entries in Claude Code's settings JSON without touching anything else.
public enum HookSettings {
    public enum Error: Swift.Error, Equatable {
        /// A hooks value we don't understand; we refuse rather than risk dropping the user's data.
        case unexpectedShape(String)
    }

    /// Checked against the event names in Claude Code 2.1.299's binary.
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
        "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd", "PreCompact",
    ]

    public static func isInstalled(in settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ((hooks[$0] as? [[String: Any]]) ?? []).contains { ours($0, command) } }
    }

    /// The events an install from the previous build has (before PreCompact).
    public static let previousEvents = events.filter { $0 != "PreCompact" }

    /// Our command is on exactly the previous build's events: an install to upgrade. Anything else (an event
    /// the user removed by hand, say) is left as it is.
    public static func isOlderInstall(in settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        // Not named `ours`: Swift 6.3 resolves the call below to the local being declared and fails.
        let installed = Set(events.filter { ((hooks[$0] as? [[String: Any]]) ?? []).contains { ours($0, command) } })
        return installed == Set(previousEvents)
    }

    public static func install(into settings: [String: Any], command: String, events: [String] = HookSettings.events)
        throws -> [String: Any] {
        var out = settings
        var hooks = try hooksDict(settings)
        for event in events {
            var list = try groups(hooks[event], event)
            if !list.contains(where: { ours($0, command) }) {
                list.append(["hooks": [["type": "command", "command": command, "timeout": timeout(for: event)]]])
            }
            hooks[event] = list
        }
        out["hooks"] = hooks
        return out
    }

    /// A permission request waits for the pet's answer (up to `PermissionWait.window`); everything else is
    /// fire-and-forget.
    public static func timeout(for event: String) -> Int {
        event == "PermissionRequest" ? PermissionWait.hookTimeout : 5
    }

    /// Our entries still on an older build's 5 s where this build wants more (the permission hook). A timeout
    /// set by hand is left alone.
    public static func hasStaleTimeouts(in settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.contains { event in
            ((hooks[event] as? [[String: Any]]) ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains {
                    $0["command"] as? String == command && ($0["timeout"] as? Int) == 5 && timeout(for: event) != 5
                }
            }
        }
    }

    /// Sets our entries' timeouts to this build's; nothing else changes.
    public static func updateTimeouts(in settings: [String: Any], command: String) throws -> [String: Any] {
        var out = settings
        var hooks = try hooksDict(settings)
        for event in events {
            guard hooks[event] != nil else { continue }
            hooks[event] = try groups(hooks[event], event).map { group in
                guard var entries = group["hooks"] as? [[String: Any]] else { return group }
                for i in entries.indices where entries[i]["command"] as? String == command
                    && entries[i]["timeout"] as? Int == 5 {
                    entries[i]["timeout"] = timeout(for: event)
                }
                var g = group
                g["hooks"] = entries
                return g
            }
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
    # Pixel Pet hook: forwards the hook JSON to the pet over a unix socket. For a permission request it prints
    # what the pet sends back (its answer, when it's on screen and the setting is on); every other connection
    # is closed at once, so only that one ever waits, and at most \(PermissionWait.ncTimeout) s.
    # Never fails Claude Code: always exit 0, stdin always drained.
    if [ -n "${PIXELPET_INTERNAL:-}" ]; then
        cat >/dev/null
        exit 0
    fi
    SOCK="$HOME/.pixelpet/pet.sock"
    if [ ! -S "$SOCK" ]; then
        cat >/dev/null
        exit 0
    fi
    # Where the session runs, for "Answer in Terminal / VS Code / Claude": [A-Za-z0-9._-] only, so it can't
    # break out of the JSON string.
    app=$(printf '%s' "${__CFBundleIdentifier:-}" | tr -cd 'A-Za-z0-9._-')
    term=$(printf '%s' "${TERM_PROGRAM:-}" | tr -cd 'A-Za-z0-9._-')
    input=$(cat)
    reply=$(printf '%s' "$input" \\
        | sed "1s/^{/{\\"pixelpet_app\\":\\"$app\\",\\"pixelpet_term\\":\\"$term\\",/" \\
        | nc -U -w \(PermissionWait.ncTimeout) "$SOCK" 2>/dev/null)
    # Only a permission request takes an answer back. Anything else that comes over the socket (something
    # other than the pet listening there) is dropped, so it can't steer other hooks.
    if printf '%s' "$input" | grep -Eq '"hook_event_name"[[:space:]]*:[[:space:]]*"PermissionRequest"'; then
        printf '%s' "$reply"
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

    /// A connection made by the previous build, before newer events existed: add the missing ones (with the
    /// usual backup), so it keeps working without a reconnect.
    public func upgradeIfOlderInstall() throws {
        guard let settings = try? readSettings() else { return }
        var updated = settings
        if HookSettings.isOlderInstall(in: updated, command: command) {
            updated = try HookSettings.install(into: updated, command: command)
        }
        // The permission hook now waits for the pet's answer, so it needs a longer timeout.
        if HookSettings.hasStaleTimeouts(in: updated, command: command) {
            updated = try HookSettings.updateTimeouts(in: updated, command: command)
        }
        guard !NSDictionary(dictionary: updated).isEqual(to: settings) else { return }
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
