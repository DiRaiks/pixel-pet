import Foundation

public struct AgentSession: Equatable, Sendable {
    public enum Status: Sendable { case idle, working, waiting, failed }

    public let id: String
    public let firstSeenAt: Date
    public var cwd: String?
    public var model: String?
    public var status = Status.idle
    public enum WaitReason: Sendable { case permission, question }
    /// What a waiting session waits for: a permission to grant, or an answer to give.
    public var waitingFor: WaitReason?
    public var currentTool: String?
    /// When the current wait for the user began.
    public var waitingSince: Date?
    /// Context window fill from the statusline (terminal sessions only).
    public var contextPercent: Double?
    public var subagents: Set<String> = []
    public var lastEventAt: Date
    public var workingSince: Date?
    /// The tool call running now (nil between calls: the model is thinking), and since when either holds.
    public var step: AgentStep?
    public var stepSince: Date?
    /// When the current turn began, and how many tool calls it made so far.
    public var turnStartedAt: Date?
    public var steps = 0
    /// How long the last finished turn took, from the prompt to the end, and its tool calls.
    public var lastTurn: TimeInterval?
    public var lastSteps = 0
    /// The last finished turn's active work, waits for the user left out.
    public var lastWork: TimeInterval = 0
    /// The app the session runs in (Terminal, VS Code, the Claude app), when the hook could tell.
    public var host: AgentHost?
    /// The session's transcript, when the hook said where it is.
    public var transcriptPath: String?
    /// Active work in this turn before the latest wait, so time spent waiting for the user isn't counted.
    var workedBefore: TimeInterval = 0
    /// The turn ended with a question for the user, so after Stop the session waits for a reply.
    var askedUser = false
    public var finishedAt: Date?
    public var failedAt: Date?
    /// tool_use_id of an AskUserQuestion / ExitPlanMode call the user hasn't answered yet.
    var pendingQuestion: String?
    /// The turn has ended but background subagents still run: the session finishes when the last one stops.
    var turnEnded = false
    /// Nothing runs until the next prompt: the turn finished, failed or was interrupted.
    var betweenTurns = false

    public init(id: String, firstSeenAt: Date, lastEventAt: Date) {
        self.id = id
        self.firstSeenAt = firstSeenAt
        self.lastEventAt = lastEventAt
    }

    public var project: String? { Self.projectName(for: cwd) }

    /// "claude-opus-5-5" or "Opus 5.5" -> "Opus"; unknown names pass through.
    public static func shortModel(_ model: String?) -> String? {
        guard let model else { return nil }
        let lower = model.lowercased()
        for family in ["opus", "sonnet", "haiku", "fable"] where lower.contains(family) {
            return family.prefix(1).uppercased() + family.dropFirst()
        }
        return model
    }

    static func projectName(for cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public enum AgentReaction: Equatable, Sendable { case finished, finishedBig, failed, compacted }

/// Live Claude Code sessions, rebuilt purely from hook events.
public struct SessionRegistry: Sendable {
    public static let staleAfter: TimeInterval = 30 * 60
    /// A working session with no tool running and no events this long was most likely interrupted (Esc fires no Stop).
    public static let silentWorkTimeout: TimeInterval = 5 * 60
    /// Only turns with at least this much active work earn a celebration; quick replies would make it noise.
    public static let celebrateAfter: TimeInterval = 20
    /// A turn this long gets the somersault with confetti instead of the ordinary jump.
    public static let bigFinishAfter: TimeInterval = 10 * 60
    static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog"]
    static let endedMemory = 500

    public private(set) var sessions: [String: AgentSession] = [:]
    /// nil for agents that always report an interrupt (Codex): a quiet turn then stays "working".
    private let silentTimeout: TimeInterval?
    /// Ended sessions still emit a few late events (e.g. the post-turn summary); they must not come back.
    /// A resumed session (same id, a new `SessionStart` or prompt) does.
    private var ended: Set<String> = []

    public init(silentWorkTimeout: TimeInterval? = SessionRegistry.silentWorkTimeout) {
        silentTimeout = silentWorkTimeout
    }

    public var ordered: [AgentSession] {
        sessions.values.sorted { ($0.firstSeenAt, $0.id) < ($1.firstSeenAt, $1.id) }
    }

    @discardableResult
    public mutating func apply(_ event: AgentEvent, at now: Date) -> AgentReaction? {
        if ended.contains(event.sessionID) {
            guard event.kind.resumesSession else { return nil }
            ended.remove(event.sessionID)
        }
        if event.kind == .sessionEnded {
            sessions.removeValue(forKey: event.sessionID)
            if ended.count >= Self.endedMemory { ended.removeAll() }
            ended.insert(event.sessionID)
            return nil
        }
        var s = sessions[event.sessionID] ?? AgentSession(id: event.sessionID, firstSeenAt: now, lastEventAt: now)
        s.lastEventAt = now
        if let cwd = event.cwd { s.cwd = cwd }
        if let host = event.host { s.host = host }
        if let path = event.transcriptPath { s.transcriptPath = path }
        // An agent's tool calls between turns (the desktop app's post-turn helper, say) aren't the session at
        // work: they must not put it back to working, where it would stay with no tool end to come.
        if s.betweenTurns, event.agentID != nil, event.kind.isToolCall {
            sessions[event.sessionID] = s
            return nil
        }
        var reaction: AgentReaction?

        switch event.kind {
        case .sessionStart(let model):
            if let model { s.model = model }
            if s.status == .idle { s.betweenTurns = true }
        case .promptSubmitted:
            s.turnStartedAt = now
            s.steps = 0
            s.step = nil
            s.stepSince = now
            s.askedUser = false
            s.turnEnded = false
            s.workedBefore = 0
            s.failedAt = nil
            s.pendingQuestion = nil
            startWorking(&s, now)
        case .toolStarted(let name, let useID):
            s.currentTool = name
            if Self.interactiveTools.contains(name) {
                enterWaiting(&s, now, for: .question)
                s.pendingQuestion = useID
            } else if s.pendingQuestion == nil {
                startWorking(&s, now)
            }
            if let step = event.step, !Self.interactiveTools.contains(name) {
                s.step = step
                s.stepSince = now
                s.steps += 1
            }
        case .toolFinished(let name, let useID):
            if s.currentTool == name {
                s.currentTool = nil
                s.step = nil
                s.stepSince = now
            }
            if let pending = s.pendingQuestion {
                if pending == useID {
                    s.pendingQuestion = nil
                    startWorking(&s, now)
                }
            } else if s.status == .waiting {
                startWorking(&s, now)
            }
        case .questionAsked:
            s.askedUser = true
        case .permissionRequested:
            enterWaiting(&s, now, for: .permission)
        case .permissionSettled:
            // Allowed (the tool runs and reports back) or denied (maybe with the turn stopped, which reports
            // nothing): back to working, and with no tool on record a stopped turn settles after the quiet timeout.
            if s.waitingFor == .permission {
                s.currentTool = nil
                startWorking(&s, now)
            }
        case .notification(let type):
            if type == "idle_prompt" {
                becomeIdle(&s)
            } else if let type, Self.waitingNotifications.contains(type) {
                enterWaiting(&s, now, for: type == "permission_prompt" ? .permission : .question)
            }
        case .compacting:
            reaction = .compacted
        case .stopped:
            // Background subagents outlive the turn: keep working until the last one reports back.
            if !s.subagents.isEmpty, !s.askedUser, s.status != .failed {
                s.turnEnded = true
                startWorking(&s, now)
            } else {
                reaction = finish(&s, now)
            }
        case .interrupted:
            // Esc stops the subagents too; their stops may never arrive.
            becomeIdle(&s)
            s.subagents.removeAll()
        case .stillWorking:
            if s.status != .waiting, s.status != .failed { startWorking(&s, now) }
        case .failed:
            becomeIdle(&s)
            s.subagents.removeAll()
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
        // The turn ended earlier and the last background subagent is done (also once a wait in between is over).
        if s.turnEnded, s.subagents.isEmpty, s.status == .working { reaction = finish(&s, now) }
        sessions[event.sessionID] = s
        return reaction
    }

    /// Statusline snapshots refresh model and context; they also keep an open terminal session from going stale.
    public mutating func apply(_ snapshot: StatuslineSnapshot, at now: Date) {
        guard !ended.contains(snapshot.sessionID) else { return }
        var s = sessions[snapshot.sessionID] ?? AgentSession(id: snapshot.sessionID, firstSeenAt: now, lastEventAt: now)
        s.lastEventAt = now
        if let cwd = snapshot.cwd { s.cwd = cwd }
        if let model = snapshot.model { s.model = model }
        s.contextPercent = snapshot.contextPercent
        sessions[snapshot.sessionID] = s
    }

    /// Drops stale sessions and settles interrupted ones. Sessions waiting for the user are never dropped.
    public mutating func prune(now: Date) {
        for (id, var s) in sessions {
            let quiet = now.timeIntervalSince(s.lastEventAt)
            if s.status == .waiting {
                // Permission prompts wait as long as it takes; an unanswered turn-end question fades.
                if s.askedUser, quiet > Self.staleAfter {
                    becomeIdle(&s)
                    s.askedUser = false
                    sessions[id] = s
                }
                continue
            }
            if quiet > Self.staleAfter {
                sessions.removeValue(forKey: id)
            } else if let silentTimeout, s.status == .working, s.currentTool == nil, quiet > silentTimeout {
                becomeIdle(&s)
                // Only a guess that the turn is over (Esc sends nothing): an agent still at work may yet report in.
                s.betweenTurns = false
                // Nothing heard for this long: subagents whose stop never came are gone too.
                s.subagents.removeAll()
                sessions[id] = s
            }
        }
    }

    /// When `prune` would next change something without a new event.
    public func nextExpiry() -> Date? {
        sessions.values.compactMap { s -> Date? in
            switch s.status {
            case .waiting: s.askedUser ? s.lastEventAt.addingTimeInterval(Self.staleAfter) : nil
            case .working where s.currentTool == nil && silentTimeout != nil:
                s.lastEventAt.addingTimeInterval(silentTimeout ?? 0)
            default: s.lastEventAt.addingTimeInterval(Self.staleAfter)
            }
        }.min()
    }

    private func startWorking(_ s: inout AgentSession, _ now: Date) {
        s.betweenTurns = false
        s.waitingFor = nil
        s.waitingSince = nil
        if s.turnStartedAt == nil { s.turnStartedAt = now }
        if s.stepSince == nil { s.stepSince = now }
        guard s.status != .working else { return }
        s.status = .working
        s.workingSince = now
    }

    private func enterWaiting(_ s: inout AgentSession, _ now: Date, for reason: AgentSession.WaitReason) {
        s.waitingFor = reason
        if s.status == .working, let since = s.workingSince { s.workedBefore += now.timeIntervalSince(since) }
        s.workingSince = nil
        if s.status != .waiting { s.waitingSince = now }
        s.status = .waiting
    }

    /// The turn is over: celebrate by how long it worked, unless it ends with a question for the user.
    private func finish(_ s: inout AgentSession, _ now: Date) -> AgentReaction? {
        var reaction: AgentReaction?
        // A turn that ends with a question isn't "done" yet: no celebration, wait for the reply instead.
        if !s.askedUser {
            let work = activeWork(s, now)
            if work >= Self.bigFinishAfter {
                reaction = .finishedBig
            } else if work >= Self.celebrateAfter {
                reaction = .finished
            }
        }
        s.lastTurn = s.turnStartedAt.map { now.timeIntervalSince($0) }
        s.lastSteps = s.steps
        s.lastWork = activeWork(s, now)
        becomeIdle(&s)
        s.finishedAt = now
        if s.askedUser {
            s.status = .waiting
            s.waitingFor = .question
            s.waitingSince = now
        }
        return reaction
    }

    private func becomeIdle(_ s: inout AgentSession) {
        s.turnEnded = false
        s.betweenTurns = true
        s.status = .idle
        s.waitingFor = nil
        s.waitingSince = nil
        s.currentTool = nil
        s.pendingQuestion = nil
        s.workingSince = nil
        s.workedBefore = 0
        s.step = nil
        s.stepSince = nil
        s.turnStartedAt = nil
        s.steps = 0
    }

    private func activeWork(_ s: AgentSession, _ now: Date) -> TimeInterval {
        s.workedBefore + (s.workingSince.map { now.timeIntervalSince($0) } ?? 0)
    }
}
