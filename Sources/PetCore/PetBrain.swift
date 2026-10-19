import Foundation

/// One block in the stack next to the pet.
public struct AgentCube: Equatable, Sendable {
    public enum Status: Sendable { case idle, working, waiting, failed, done }
    public var status: Status
    public var subagents: Int
    public init(status: Status, subagents: Int) {
        self.status = status
        self.subagents = subagents
    }
}

/// Turns the session list into what the pet shows. Pure, so priorities are easy to test.
public enum PetBrain {
    public static let errorWindow: TimeInterval = 3
    public static let doneFlash: TimeInterval = 1.5

    public static func baseState(for sessions: [AgentSession], limits: UsageLimits? = nil, now: Date) -> PetState {
        if sessions.contains(where: { isFreshFailure($0, now) }) { return .error }
        if sessions.contains(where: { $0.status == .waiting }) { return .alert }
        if limits?.current(at: now).isLow == true { return .lowLimit }
        if sessions.contains(where: { $0.status == .working }) { return .working }
        return .idle
    }

    public static func cubes(for sessions: [AgentSession], now: Date) -> [AgentCube] {
        sessions.map { s in
            let status: AgentCube.Status
            switch s.status {
            case .working: status = .working
            case .waiting: status = .waiting
            case .failed: status = .failed
            case .idle:
                let flashing = s.finishedAt.map { now.timeIntervalSince($0) < doneFlash } ?? false
                status = flashing ? .done : .idle
            }
            return AgentCube(status: status, subagents: s.subagents.count)
        }
    }

    /// When the picture changes without a new event (error window or done flash ends).
    public static func nextChange(for sessions: [AgentSession], now: Date) -> Date? {
        let expiries = sessions.flatMap { s -> [Date] in
            [s.failedAt.map { $0.addingTimeInterval(errorWindow) }, s.finishedAt.map { $0.addingTimeInterval(doneFlash) }]
                .compactMap { $0 }
        }
        return expiries.filter { $0 > now }.min()
    }

    /// At home the pet hides; alerts and errors bring it out to watch. Do-not-disturb lets only errors through.
    public static func homeState(for base: PetState, doNotDisturb: Bool) -> PetState {
        switch base {
        case .error: .peekHold
        case .alert: doNotDisturb ? .burrowed : .peekHold
        default: .burrowed
        }
    }

    /// One-shots at home become a quick peek (or nothing under do-not-disturb).
    public static func homeReaction(to oneShot: PetState, doNotDisturb: Bool) -> PetState? {
        doNotDisturb ? nil : .peek
    }

    /// With nothing going on and the user away for a while, the pet dozes off.
    public static func restState(mood: PetState, userIdle: TimeInterval, sleepAfter: TimeInterval) -> PetState {
        guard mood == .idle, sleepAfter > 0, userIdle >= sleepAfter else { return mood }
        return .sleep
    }

    public static func activeCount(_ sessions: [AgentSession]) -> Int {
        sessions.filter { $0.status == .working || $0.status == .waiting }.count
    }

    private static func isFreshFailure(_ s: AgentSession, _ now: Date) -> Bool {
        s.status == .failed && (s.failedAt.map { now.timeIntervalSince($0) < errorWindow } ?? false)
    }
}
