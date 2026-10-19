import Foundation

public struct LimitWindow: Codable, Equatable, Sendable {
    /// 0...100 (can exceed 100 once a limit is overrun).
    public var usedPercent: Double
    public var resetsAt: Date
    public init(usedPercent: Double, resetsAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Subscription usage windows as last reported by Claude Code.
public struct UsageLimits: Codable, Equatable, Sendable {
    public static let fiveHourLow = 85.0
    public static let sevenDayLow = 90.0

    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var observedAt: Date

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?, observedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.observedAt = observedAt
    }

    /// Reads a `rate_limit_event` line from `claude -p --output-format stream-json` (utilization is 0...1).
    public static func fromStreamLine(_ line: String, observedAt: Date) -> UsageLimits? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              json["type"] as? String == "rate_limit_event",
              let windows = (json["rate_limit_info"] as? [String: Any])?["unifiedWindows"] as? [String: Any]
        else { return nil }
        func window(_ key: String) -> LimitWindow? {
            guard let w = windows[key] as? [String: Any], let used = number(w["utilization"]),
                  let reset = number(w["resetsAt"]) else { return nil }
            // Utilization is a 0...1 fraction; keep two decimals so 0.07 reads as 7, not 7.000000000000001.
            return LimitWindow(usedPercent: (used * 10_000).rounded() / 100, resetsAt: Date(timeIntervalSince1970: reset))
        }
        let limits = UsageLimits(fiveHour: window("five_hour"), sevenDay: window("seven_day"), observedAt: observedAt)
        return limits.isEmpty ? nil : limits
    }

    public var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    /// Combines two observations window by window. Usage within one window only grows, so the window that
    /// resets later wins, and for the same window the higher usage wins. Arrival time alone means little:
    /// an idle terminal can re-send an old window long after a fresher probe.
    public func merged(with other: UsageLimits) -> UsageLimits {
        let five = Self.pick(fiveHour, observedAt, other.fiveHour, other.observedAt)
        let week = Self.pick(sevenDay, observedAt, other.sevenDay, other.observedAt)
        let seen = [five.at, week.at].compactMap { $0 }.max() ?? max(observedAt, other.observedAt)
        return UsageLimits(fiveHour: five.window, sevenDay: week.window, observedAt: seen)
    }

    private static func pick(_ a: LimitWindow?, _ aAt: Date, _ b: LimitWindow?, _ bAt: Date) -> (window: LimitWindow?, at: Date?) {
        switch (a, b) {
        case (nil, nil): return (nil, nil)
        case let (x?, nil): return (x, aAt)
        case let (nil, y?): return (y, bAt)
        case let (x?, y?):
            if x.resetsAt != y.resetsAt { return x.resetsAt > y.resetsAt ? (x, aAt) : (y, bAt) }
            if x.usedPercent != y.usedPercent { return x.usedPercent > y.usedPercent ? (x, aAt) : (y, bAt) }
            return aAt >= bAt ? (x, aAt) : (y, bAt)
        }
    }

    /// Same numbers, regardless of when they were seen; used to avoid rewriting the config for nothing.
    public func sameWindows(as other: UsageLimits) -> Bool {
        fiveHour == other.fiveHour && sevenDay == other.sevenDay
    }

    /// Drops windows that have already reset; their old percentage no longer means anything.
    public func current(at now: Date) -> UsageLimits {
        UsageLimits(fiveHour: fiveHour.flatMap { $0.resetsAt > now ? $0 : nil },
                    sevenDay: sevenDay.flatMap { $0.resetsAt > now ? $0 : nil }, observedAt: observedAt)
    }

    public func nextReset(after now: Date) -> Date? {
        [fiveHour?.resetsAt, sevenDay?.resetsAt].compactMap { $0 }.filter { $0 > now }.min()
    }

    /// A limit reached: agents can't work until it resets.
    public var isSpent: Bool {
        (fiveHour?.usedPercent ?? 0) >= 100 || (sevenDay?.usedPercent ?? 0) >= 100
    }

    /// The 5-hour window that had real use in it reset: gone (its time passed) or replaced by a newer window
    /// with less use.
    public static func refilled(before: LimitWindow?, after: LimitWindow?) -> Bool {
        guard let before, before.usedPercent >= 10 else { return false }
        guard let after else { return true }
        // A genuinely newer window, not the same one reported with a slightly different reset time.
        return after.resetsAt > before.resetsAt.addingTimeInterval(3600) && after.usedPercent < before.usedPercent
    }

    public var isLow: Bool {
        (fiveHour?.usedPercent ?? 0) >= Self.fiveHourLow || (sevenDay?.usedPercent ?? 0) >= Self.sevenDayLow
    }

    /// How many interior rows of the body look "used up", following the 5-hour window.
    public func drainRows(interior: Int) -> Int {
        let used = min(max(fiveHour?.usedPercent ?? 0, 0), 100)
        return Int((used / 100 * Double(interior)).rounded(.down))
    }
}

func number(_ value: Any?) -> Double? {
    switch value {
    case let n as NSNumber: n.doubleValue
    default: nil
    }
}

/// What a terminal session's statusline command receives (Claude Code doesn't run it for desktop sessions).
public struct StatuslineSnapshot: Equatable, Sendable {
    public var sessionID: String
    public var cwd: String?
    public var model: String?
    public var contextPercent: Double?
    public var limits: UsageLimits?

    public init(sessionID: String, cwd: String?, model: String?, contextPercent: Double?, limits: UsageLimits?) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.model = model
        self.contextPercent = contextPercent
        self.limits = limits
    }
}

extension StatuslineSnapshot {
    /// Opt-in event log line: ids, project and numbers only.
    public var logLine: String {
        let project = AgentSession.projectName(for: cwd) ?? "-"
        let ctx = contextPercent.map { "ctx \(Int($0.rounded()))%" } ?? "ctx -"
        let five = limits?.fiveHour.map { "5h \(Int($0.usedPercent.rounded()))%" } ?? "5h -"
        return "\(sessionID.prefix(8)) \(project) statusline \(model ?? "-") \(ctx) \(five)"
    }
}

/// Anything that arrives on the pet socket.
public enum Inbound: Equatable, Sendable {
    case hook(AgentEvent)
    case statusline(StatuslineSnapshot)

    public static func parse(_ data: Data, at now: Date) -> Inbound? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Some Claude Code versions tag the statusline payload as a "Status" hook; route it by shape instead.
        if let name = json["hook_event_name"] as? String, name != "Status" { return AgentEvent.parse(data).map(Inbound.hook) }
        guard let session = json["session_id"] as? String, !session.isEmpty,
              json["model"] is [String: Any] || json["context_window"] is [String: Any]
        else { return nil }
        let model = json["model"] as? [String: Any]
        let context = json["context_window"] as? [String: Any]
        let rates = json["rate_limits"] as? [String: Any]
        func window(_ key: String) -> LimitWindow? {
            guard let w = rates?[key] as? [String: Any], let used = number(w["used_percentage"]),
                  let reset = number(w["resets_at"]) else { return nil }
            return LimitWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
        }
        let limits = UsageLimits(fiveHour: window("five_hour"), sevenDay: window("seven_day"), observedAt: now)
        return .statusline(StatuslineSnapshot(
            sessionID: session,
            cwd: json["cwd"] as? String,
            model: (model?["display_name"] as? String) ?? (model?["id"] as? String),
            contextPercent: number(context?["used_percentage"]),
            limits: limits.isEmpty ? nil : limits
        ))
    }
}
