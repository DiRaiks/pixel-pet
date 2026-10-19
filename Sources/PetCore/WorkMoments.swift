import Foundation

/// How long the agents have been at it, shown by what piles up on the desk.
public enum WorkStage: Int, Comparable, Sendable {
    case fresh, mug, headband

    public static let mugAfter: TimeInterval = 10 * 60
    public static let headbandAfter: TimeInterval = 30 * 60

    /// `worked`: active work so far in the longest-running current turn (nil when nothing works).
    public static func stage(worked: TimeInterval?) -> WorkStage {
        guard let worked else { return .fresh }
        return worked >= headbandAfter ? .headband : worked >= mugAfter ? .mug : .fresh
    }

    /// When the next prop appears if the work goes on, so the monitor can wake up for it.
    public static func nextChange(worked: TimeInterval?, now: Date) -> Date? {
        guard let worked else { return nil }
        return [mugAfter, headbandAfter].first { $0 > worked }.map { now.addingTimeInterval($0 - worked) }
    }

    public static func < (a: WorkStage, b: WorkStage) -> Bool { a.rawValue < b.rawValue }
}

/// Small moments at the keyboard, so hours of typing don't look like one loop: now and then a sip, a
/// stretch, a pause to think or a burst of fast typing; and a look over when an agent block changes.
public enum WorkMoments {
    public static let pool: [PetState] = [.workSip, .workStretch, .workThink, .workRush]
    /// Seconds between moments: often enough to notice over a long task, rare enough not to fuss.
    public static let range: ClosedRange<TimeInterval> = 45...120
    /// A look over at the blocks at most this often.
    public static let glanceCooldown: TimeInterval = 8

    public static func delay() -> TimeInterval { Double.random(in: range) }

    /// A moment other than the last one; `roll` is any random number.
    public static func pick(after last: PetState?, roll: Int) -> PetState {
        let choices = pool.filter { $0 != last }
        return choices[abs(roll) % choices.count]
    }

    /// Worth a look: an agent on this side finished, failed, started waiting or working, or a new one joined
    /// the others. Not: subagents, the green flash fading, a session dropping off (the blocks after it then
    /// move down a slot, so slots are only compared while the count stays the same), or the first blocks
    /// showing up at launch.
    public static func noticeable(old: [AgentCube], new: [AgentCube]) -> Bool {
        guard !old.isEmpty else { return false }
        if new.count > old.count { return true }
        guard new.count == old.count else { return false }
        return zip(old, new).contains { before, after in
            guard before.status != after.status else { return false }
            switch after.status {
            case .done, .failed, .waiting: return true
            case .working: return before.status == .idle || before.status == .done
            case .idle: return false
            }
        }
    }
}

extension PetState {
    /// At the keyboard: typing and its moments. These show the desk props.
    public var isAtDesk: Bool {
        switch self {
        case .working, .workSip, .workStretch, .workThink, .workRush, .glanceLeft, .glanceRight: true
        default: false
        }
    }
}
