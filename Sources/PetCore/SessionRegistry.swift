import Foundation

public struct AgentSession: Equatable, Sendable {
    public enum Status: Sendable { case idle, working, waiting, failed }

    public let id: String
    public let firstSeenAt: Date
    public var cwd: String?
    public var model: String?
    public var status = Status.idle
    public var currentTool: String?
    public var subagents: Set<String> = []
    public var lastEventAt: Date
    public var workingSince: Date?
    /// Active work in this turn before the latest wait, so time spent waiting for the user isn't counted.
    var workedBefore: TimeInterval = 0
    public var finishedAt: Date?
    public var failedAt: Date?
    /// tool_use_id of an AskUserQuestion / ExitPlanMode call the user hasn't answered yet.
    var pendingQuestion: String?

    public init(id: String, firstSeenAt: Date, lastEventAt: Date) {
        self.id = id
        self.firstSeenAt = firstSeenAt
        self.lastEventAt = lastEventAt
    }

    public var project: String? { Self.projectName(for: cwd) }

    static func projectName(for cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public enum AgentReaction: Equatable, Sendable { case finished, failed }

/// Live Claude Code sessions, rebuilt purely from hook events.
public struct SessionRegistry: Sendable {
    public static let staleAfter: TimeInterval = 30 * 60
    /// A working session with no tool running and no events this long was most likely interrupted (Esc fires no Stop).
    public static let silentWorkTimeout: TimeInterval = 5 * 60
    /// Only turns with at least this much active work earn a celebration; quick replies would make it noise.
    public static let celebrateAfter: TimeInterval = 20
    static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog"]
    static let endedMemory = 500

    public private(set) var sessions: [String: AgentSession] = [:]
    /// Ended sessions still emit a few late events (e.g. the post-turn summary); they must not come back.
    private var ended: Set<String> = []

    public init() {}

    public var ordered: [AgentSession] {
        sessions.values.sorted { ($0.firstSeenAt, $0.id) < ($1.firstSeenAt, $1.id) }
    }

    @discardableResult
    public mutating func apply(_ event: AgentEvent, at now: Date) -> AgentReaction? {
        guard !ended.contains(event.sessionID) else { return nil }
        if event.kind == .sessionEnded {
            sessions.removeValue(forKey: event.sessionID)
            if ended.count >= Self.endedMemory { ended.removeAll() }
            ended.insert(event.sessionID)
            return nil
        }
        var s = sessions[event.sessionID] ?? AgentSession(id: event.sessionID, firstSeenAt: now, lastEventAt: now)
        s.lastEventAt = now
        if let cwd = event.cwd { s.cwd = cwd }
        var reaction: AgentReaction?

        switch event.kind {
        case .sessionStart(let model):
            if let model { s.model = model }
        case .promptSubmitted:
            s.workedBefore = 0
            s.subagents.removeAll()
            s.failedAt = nil
            s.pendingQuestion = nil
            startWorking(&s, now)
        case .toolStarted(let name, let useID):
            s.currentTool = name
            if Self.interactiveTools.contains(name) {
                enterWaiting(&s, now)
                s.pendingQuestion = useID
            } else if s.pendingQuestion == nil {
                startWorking(&s, now)
            }
        case .toolFinished(let name, let useID):
            if s.currentTool == name { s.currentTool = nil }
            if let pending = s.pendingQuestion {
                if pending == useID {
                    s.pendingQuestion = nil
                    startWorking(&s, now)
                }
            } else if s.status == .waiting {
                startWorking(&s, now)
            }
        case .permissionRequested:
            enterWaiting(&s, now)
        case .notification(let type):
            if type == "idle_prompt" {
                becomeIdle(&s)
            } else if let type, Self.waitingNotifications.contains(type) {
                enterWaiting(&s, now)
            }
        case .stopped:
            if activeWork(s, now) >= Self.celebrateAfter { reaction = .finished }
            becomeIdle(&s)
            s.finishedAt = now
        case .failed:
            becomeIdle(&s)
            s.status = .failed
            s.failedAt = now
            reaction = .failed
        case .subagentStarted(let id):
            s.subagents.insert(id)
        case .subagentStopped(let id):
            s.subagents.remove(id)
        case .sessionEnded:
            break
        }
        sessions[event.sessionID] = s
        return reaction
    }

    /// Drops stale sessions and settles interrupted ones. Sessions waiting for the user are never dropped.
    public mutating func prune(now: Date) {
        for (id, var s) in sessions {
            let quiet = now.timeIntervalSince(s.lastEventAt)
            if s.status == .waiting { continue }
            if quiet > Self.staleAfter {
                sessions.removeValue(forKey: id)
            } else if s.status == .working, s.currentTool == nil, quiet > Self.silentWorkTimeout {
                becomeIdle(&s)
                sessions[id] = s
            }
        }
    }

    /// When `prune` would next change something without a new event.
    public func nextExpiry() -> Date? {
        sessions.values.compactMap { s -> Date? in
            switch s.status {
            case .waiting: nil
            case .working where s.currentTool == nil: s.lastEventAt.addingTimeInterval(Self.silentWorkTimeout)
            default: s.lastEventAt.addingTimeInterval(Self.staleAfter)
            }
        }.min()
    }

    private func startWorking(_ s: inout AgentSession, _ now: Date) {
        guard s.status != .working else { return }
        s.status = .working
        s.workingSince = now
    }

    private func enterWaiting(_ s: inout AgentSession, _ now: Date) {
        if s.status == .working, let since = s.workingSince { s.workedBefore += now.timeIntervalSince(since) }
        s.workingSince = nil
        s.status = .waiting
    }

    private func becomeIdle(_ s: inout AgentSession) {
        s.status = .idle
        s.currentTool = nil
        s.pendingQuestion = nil
        s.workingSince = nil
        s.workedBefore = 0
    }

    private func activeWork(_ s: AgentSession, _ now: Date) -> TimeInterval {
        s.workedBefore + (s.workingSince.map { now.timeIntervalSince($0) } ?? 0)
    }
}
