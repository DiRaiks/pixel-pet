import Foundation

/// Rubbing the cursor back and forth over the pet pets it: a few changes of direction in quick succession.
public struct PettingDetector: Sendable {
    public static let reversals = 3
    public static let window: TimeInterval = 1.2
    /// Smaller wiggles are just a hand resting on the mouse.
    public static let minStroke = 4.0
    public static let cooldown: TimeInterval = 10

    private var lastX: Double?
    private var direction = 0
    private var strokeStart: Double?
    private var turns: [TimeInterval] = []
    private var lastPetted: TimeInterval = -.infinity

    public init() {}

    /// Feed cursor x positions (points) over the pet; true when this move completes a petting.
    public mutating func move(x: Double, at time: TimeInterval) -> Bool {
        defer { lastX = x }
        guard let lastX, x != lastX else { return false }
        let dir = x > lastX ? 1 : -1
        if dir != direction {
            // A turn counts once the stroke before it was long enough.
            if direction != 0, let start = strokeStart, abs(lastX - start) >= Self.minStroke { turns.append(time) }
            direction = dir
            strokeStart = lastX
        }
        turns.removeAll { time - $0 > Self.window }
        guard turns.count >= Self.reversals, time - lastPetted >= Self.cooldown else { return false }
        lastPetted = time
        turns.removeAll()
        return true
    }

    /// The cursor left the pet: strokes don't carry over.
    public mutating func reset() {
        lastX = nil
        direction = 0
        strokeStart = nil
        turns.removeAll()
    }
}

/// Holiday props by the Mac's date: a jack-o'-lantern the last week of October, a little fir over New Year.
public enum Holiday: Sendable, Equatable {
    case halloween, newYear

    public static func on(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Holiday? {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let month = c.month, let day = c.day else { return nil }
        switch (month, day) {
        case (10, 25...31): return .halloween
        case (12, 20...31), (1, 1...7): return .newYear
        default: return nil
        }
    }
}

/// While an agent waits on you for over a minute, the pet waves now and then.
public enum WaitNudge {
    public static let after: TimeInterval = 60
    public static let every: TimeInterval = 45

    /// When the next wave is due for a wait that started at `since`, given the last wave.
    public static func next(since: Date, lastWave: Date?) -> Date {
        let first = since.addingTimeInterval(after)
        guard let lastWave, lastWave >= since else { return first }
        return max(first, lastWave.addingTimeInterval(every))
    }
}
