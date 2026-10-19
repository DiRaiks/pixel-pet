import Foundation

/// Reads a Codex session file (`~/.codex/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`) line by line and turns
/// it into the same `AgentEvent`s the Claude Code hooks produce, plus Codex's own limits.
///
/// The format is Codex's internal one, so the parsing is lenient: unknown lines are skipped. What it gives:
/// a turn starts (`task_started`), runs (any line carrying a `turn_id`), ends (`task_complete`), is cut short
/// (`turn_aborted`) or fails (`error`). Waiting for an approval isn't written to the file, so Codex agents
/// never show as waiting.
public struct CodexRollout: Sendable {
    public enum Output: Sendable {
        case event(AgentEvent, at: Date)
        case limits(UsageLimits)
    }

    /// From the file name; `session_meta` (the first line) confirms it.
    public let sessionIDFromFileName: String?
    public private(set) var sessionID: String?
    private var cwd: String?
    /// Subagent threads write their own files; they are part of their parent's work, not separate agents.
    public private(set) var isSubagent = false
    /// The turn running now, if any; every line inside it is a sign of life.
    private var openTurn: String?
    /// Turns already finished or aborted: their late lines must not bring them back.
    private var closedTurns: [String] = []

    /// Events older than this when they are read are history: they update the picture, nothing to react to.
    public static let liveWindow: TimeInterval = 10

    public static func isLive(_ at: Date, now: Date) -> Bool { now.timeIntervalSince(at) <= liveWindow }

    public init(fileName: String) {
        let stem = (fileName as NSString).deletingPathExtension
        let tail = stem.count >= 36 ? String(stem.suffix(36)) : ""
        sessionIDFromFileName = UUID(uuidString: tail) != nil && stem.hasPrefix("rollout-") ? tail.lowercased() : nil
        sessionID = sessionIDFromFileName
    }

    public mutating func read(_ line: String, now: Date = Date()) -> [Output] {
        guard !isSubagent, let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return [] }
        let payload = json["payload"] as? [String: Any] ?? [:]
        let at = (json["timestamp"] as? String).flatMap(Self.parseTime) ?? now

        switch type {
        case "session_meta":
            if let source = payload["thread_source"] as? String, source != "user" {
                isSubagent = true
                return []
            }
            if let id = payload["id"] as? String, !id.isEmpty { sessionID = id }
            if let dir = payload["cwd"] as? String { cwd = dir }
            return event(.sessionStart(model: nil), at)
        case "compacted":
            return event(.compacting, at)
        case "turn_context":
            if let dir = payload["cwd"] as? String { cwd = dir }
            if let turn = payload["turn_id"] as? String, !closedTurns.contains(turn) { openTurn = turn }
            return event(.sessionStart(model: payload["model"] as? String), at)
        case "event_msg":
            let turn = payload["turn_id"] as? String
            switch payload["type"] as? String {
            case "task_started":
                openTurn = turn ?? "?"
                return event(.promptSubmitted, at)
            case "task_complete":
                close(turn)
                return event(.stopped, at)
            case "turn_aborted":
                close(turn)
                return event(.interrupted, at)
            case "error": return event(.failed, at)
            case "token_count":
                return Self.limits(payload["rate_limits"], at).map { [.limits($0)] } ?? []
            default: break
            }
        default: break
        }
        // Read from the middle of a file, a turn id is how we learn that a turn is running.
        if let turn = payload["turn_id"] as? String {
            guard !closedTurns.contains(turn) else { return [] }
            openTurn = turn
        }
        return openTurn == nil ? [] : event(.stillWorking, at)
    }

    private mutating func close(_ turn: String?) {
        if let turn {
            closedTurns.append(turn)
            if closedTurns.count > 64 { closedTurns.removeFirst(closedTurns.count - 64) }
        }
        openTurn = nil
    }

    /// The JSON-RPC answer (result or error) to the request with this `id`.
    public static func isResponse(_ line: String, id: Int) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return false }
        return (json["id"] as? Int) == id && (json["result"] != nil || json["error"] != nil)
    }

    private func event(_ kind: AgentEvent.Kind, _ at: Date) -> [Output] {
        guard let sessionID else { return [] }
        return [.event(AgentEvent(sessionID: sessionID, cwd: cwd, kind: kind), at: at)]
    }

    /// The answer to an app-server `account/rateLimits/read` request with this `id`, as limits.
    public static func appServerLimits(_ line: String, id: Int, observedAt: Date) -> UsageLimits? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              (json["id"] as? Int) == id, let result = json["result"] as? [String: Any]
        else { return nil }
        return limits(result["rateLimits"], observedAt, keys: ("usedPercent", "resetsAt", "windowDurationMins"))
    }

    /// `primary` / `secondary` windows; which is which is told by their length (5 hours, 7 days).
    /// Session files spell the fields in snake_case, the app-server protocol in camelCase.
    static func limits(_ value: Any?, _ at: Date,
                       keys: (used: String, reset: String, minutes: String) = ("used_percent", "resets_at", "window_minutes"))
        -> UsageLimits? {
        guard let rates = value as? [String: Any] else { return nil }
        var fiveHour: LimitWindow?, sevenDay: LimitWindow?
        for key in ["primary", "secondary"] {
            guard let w = rates[key] as? [String: Any], let used = number(w[keys.used]),
                  let reset = number(w[keys.reset]) else { continue }
            let window = LimitWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
            // Without a length, primary is the 5-hour window and secondary the weekly one.
            let long = number(w[keys.minutes]).map { $0 >= 24 * 60 } ?? (key == "secondary")
            if long { sevenDay = window } else { fiveHour = window }
        }
        let limits = UsageLimits(fiveHour: fiveHour, sevenDay: sevenDay, observedAt: at)
        return limits.isEmpty ? nil : limits
    }

    private static let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso = Date.ISO8601FormatStyle()

    static func parseTime(_ text: String) -> Date? {
        (try? isoFractional.parse(text)) ?? (try? iso.parse(text))
    }
}
