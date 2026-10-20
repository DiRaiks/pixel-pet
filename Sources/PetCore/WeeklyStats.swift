import Foundation

/// Sums per day for the weekly recap: agent time, turns and steps per project, time spent waiting for the
/// user, permissions answered from the pet, and the 5-hour limit. Numbers and project folder names only.
public struct AgentStats: Codable, Equatable, Sendable {
    public struct ProjectDay: Codable, Equatable, Sendable {
        public var claude: TimeInterval = 0
        public var codex: TimeInterval = 0
        public var turns = 0
        public var steps = 0
    }

    public struct Day: Codable, Equatable, Sendable {
        public var projects: [String: ProjectDay] = [:]
        public var waits = 0
        public var waited: TimeInterval = 0
        public var answeredInPet = 0
        public var limitPeak: Double?
        public var limitHits = 0
        public var longestTurn: TimeInterval = 0
        public var longestProject: String?
    }

    /// Keyed by local date, "yyyy-MM-dd".
    public private(set) var days: [String: Day] = [:]
    /// The 5-hour window that was last seen at 100%, so a window counts as one hit however often it's seen.
    var lastHitWindow: Date?

    public static let keepWeeks = 8

    public init() {}

    public enum Agent: Sendable { case claude, codex }

    /// A finished turn: its active time (waits for the user left out) and tool calls, on the day it ended.
    public mutating func recordTurn(project: String, agent: Agent, active: TimeInterval, steps: Int, at date: Date) {
        update(date) { day in
            var p = day.projects[project] ?? ProjectDay()
            switch agent {
            case .claude: p.claude += active
            case .codex: p.codex += active
            }
            p.turns += 1
            p.steps += steps
            day.projects[project] = p
            if active > day.longestTurn {
                day.longestTurn = active
                day.longestProject = project
            }
        }
    }

    /// The user answered a wait (permission or question) after this long.
    public mutating func recordWait(_ seconds: TimeInterval, at date: Date) {
        update(date) { day in
            day.waits += 1
            day.waited += max(0, seconds)
        }
    }

    public mutating func recordAnswerInPet(at date: Date) {
        update(date) { $0.answeredInPet += 1 }
    }

    /// The 5-hour window's use as seen now.
    public mutating func recordLimit(_ window: LimitWindow, at date: Date) {
        let hit = window.usedPercent >= 100 && lastHitWindow != window.resetsAt
        if hit { lastHitWindow = window.resetsAt }
        update(date) { day in
            day.limitPeak = max(day.limitPeak ?? 0, min(window.usedPercent, 100))
            if hit { day.limitHits += 1 }
        }
    }

    /// Drops days older than `keepWeeks` weeks before the week of `now`.
    public mutating func prune(now: Date, calendar: Calendar = .recap) {
        guard let start = calendar.date(byAdding: .weekOfYear, value: -Self.keepWeeks, to: Week.containing(now, calendar).start)
        else { return }
        let first = Self.key(start, calendar)
        days = days.filter { $0.key >= first }
    }

    public var isEmpty: Bool { days.isEmpty }

    private mutating func update(_ date: Date, calendar: Calendar = .recap, _ change: (inout Day) -> Void) {
        let key = Self.key(date, calendar)
        var day = days[key] ?? Day()
        change(&day)
        days[key] = day
    }

    static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func day(_ date: Date, calendar: Calendar = .recap) -> Day? { days[Self.key(date, calendar)] }

    /// The week starting on Monday that holds `date`.
    public struct Week: Equatable, Sendable {
        public let start: Date
        public let days: [Date]

        public static func containing(_ date: Date, _ calendar: Calendar = .recap) -> Week {
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            let start = interval?.start ?? calendar.startOfDay(for: date)
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            return Week(start: start, days: days)
        }

        public var previous: Week {
            Week.containing(Calendar.recap.date(byAdding: .day, value: -7, to: start) ?? start)
        }
    }

    public func summary(of week: Week, calendar: Calendar = .recap) -> WeekSummary {
        var s = WeekSummary(week: week)
        var perProject: [String: TimeInterval] = [:]
        for (i, date) in week.days.enumerated() {
            guard let day = days[Self.key(date, calendar)] else { continue }
            s.daysWithData += 1
            for (name, p) in day.projects {
                s.perDay[i].claude += p.claude
                s.perDay[i].codex += p.codex
                s.turns += p.turns
                s.steps += p.steps
                perProject[name, default: 0] += p.claude + p.codex
            }
            s.waits += day.waits
            s.waited += day.waited
            s.answeredInPet += day.answeredInPet
            if let peak = day.limitPeak { s.limitPeak = max(s.limitPeak ?? 0, peak) }
            s.limitHits += day.limitHits
            if day.longestTurn > (s.longest?.seconds ?? 0), let project = day.longestProject {
                s.longest = (day.longestTurn, project, i)
            }
        }
        let ranked = perProject.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        s.projects = ranked.prefix(WeekSummary.shownProjects).map { ($0.key, $0.value) }
        let rest = ranked.dropFirst(WeekSummary.shownProjects)
        if !rest.isEmpty { s.others = (rest.count, rest.reduce(0) { $0 + $1.value }) }
        let before = week.previous
        let earlier = before.days.compactMap { days[Self.key($0, calendar)] }
        if !earlier.isEmpty {
            s.previousTotal = earlier.reduce(0) { $0 + $1.projects.values.reduce(0) { $0 + $1.claude + $1.codex } }
        }
        return s
    }
}

/// One week of `AgentStats`, ready to show.
public struct WeekSummary: Sendable {
    public static let shownProjects = 3

    public let week: AgentStats.Week
    /// Monday first.
    public var perDay = Array(repeating: (claude: TimeInterval(0), codex: TimeInterval(0)), count: 7)
    public var turns = 0
    public var steps = 0
    public var projects: [(name: String, seconds: TimeInterval)] = []
    /// The projects past the top ones: how many, and their time together.
    public var others: (count: Int, seconds: TimeInterval)?
    public var longest: (seconds: TimeInterval, project: String, weekday: Int)?
    public var waits = 0
    public var waited: TimeInterval = 0
    public var answeredInPet = 0
    public var limitPeak: Double?
    public var limitHits = 0
    public var daysWithData = 0
    /// Agent time the week before, when there's any record of it.
    public var previousTotal: TimeInterval?

    public var total: TimeInterval { perDay.reduce(0) { $0 + $1.claude + $1.codex } }

    /// Change against the week before, as a fraction (0.12 for +12%); nil without a week to compare to.
    public var change: Double? {
        guard let previousTotal, previousTotal >= 60 else { return nil }
        return total / previousTotal - 1
    }

    /// Enough to be worth a Monday newspaper: agents worked on at least two days.
    public var worthShowing: Bool {
        perDay.filter { $0.claude + $0.codex > 0 }.count >= 2
    }
}

extension Calendar {
    /// Weeks start on Monday, in the Mac's time zone.
    public static var recap: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }
}

/// `~/.pixelpet/stats.json`. An unreadable file starts the stats over rather than stopping the app.
public struct StatsStore: Sendable {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelpet/stats.json")
    }

    public init(url: URL = StatsStore.defaultURL) {
        self.url = url
    }

    public func load() -> AgentStats {
        guard let data = try? Data(contentsOf: url) else { return AgentStats() }
        return (try? JSONDecoder().decode(AgentStats.self, from: data)) ?? AgentStats()
    }

    public func save(_ stats: AgentStats) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(stats).write(to: url, options: .atomic)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// When the newspaper comes out: once a week, from Monday 6:00 (or the first time the pet is up later that
/// week), when last week has agents working on at least two days.
public enum RecapPlan {
    public static let fromHour = 6

    /// The Monday of `now`'s week as a stats key, to remember the newspaper by.
    public static func weekKey(_ now: Date, calendar: Calendar = .recap) -> String {
        AgentStats.key(AgentStats.Week.containing(now, calendar).start, calendar)
    }

    public static func due(now: Date, shownFor: String?, stats: AgentStats, calendar: Calendar = .recap) -> Bool {
        let week = AgentStats.Week.containing(now, calendar)
        guard shownFor != weekKey(now, calendar: calendar),
              let opens = calendar.date(byAdding: .hour, value: fromHour, to: week.start), now >= opens else { return false }
        return stats.summary(of: week.previous, calendar: calendar).worthShowing
    }
}
