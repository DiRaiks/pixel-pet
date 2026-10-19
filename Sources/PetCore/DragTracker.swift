/// Tells a click from a drag and measures release velocity for a flick.
public struct DragTracker: Sendable {
    public enum Result: Equatable, Sendable {
        case click
        case drag(velocity: PetPoint)
    }

    static let threshold = 4.0
    /// Only motion this recent counts toward the flick.
    static let velocityWindow = 0.1

    private let start: PetPoint
    private var samples: [(point: PetPoint, time: Double)]
    public private(set) var isDragging = false
    /// Shaken: the horizontal direction flipped at least `shakeReversals` times, each after a real swing,
    /// within `shakeWindow` seconds.
    public private(set) var isShaken = false
    static let shakeReversals = 4
    static let shakeWindow = 1.2
    static let shakeSwing = 20.0
    private var direction = 0
    private var swingStart = 0.0
    private var reversals: [Double] = []

    public init(start: PetPoint, time: Double) {
        self.start = start
        samples = [(start, time)]
        swingStart = start.x
    }

    public mutating func move(to point: PetPoint, time: Double) {
        samples.append((point, time))
        samples.removeAll { time - $0.time > Self.velocityWindow * 2 }
        if !isDragging, hypot(point.x - start.x, point.y - start.y) >= Self.threshold {
            isDragging = true
        }
        trackShake(point, time)
    }

    private mutating func trackShake(_ point: PetPoint, _ time: Double) {
        guard samples.count >= 2 else { swingStart = point.x; return }
        let dx = point.x - samples[samples.count - 2].point.x
        guard dx != 0 else { return }
        let now = dx > 0 ? 1 : -1
        if now != direction {
            // A turn counts once the swing before it went far enough.
            if direction != 0, abs(samples[samples.count - 2].point.x - swingStart) >= Self.shakeSwing { reversals.append(time) }
            direction = now
            swingStart = samples[samples.count - 2].point.x
        }
        reversals.removeAll { time - $0 > Self.shakeWindow }
        if reversals.count >= Self.shakeReversals { isShaken = true }
    }

    public func end(time: Double) -> Result {
        guard isDragging else { return .click }
        let recent = samples.filter { time - $0.time <= Self.velocityWindow + 1e-9 }
        guard let first = recent.first, let last = recent.last, last.time > first.time else {
            return .drag(velocity: PetPoint(x: 0, y: 0))
        }
        let dt = last.time - first.time
        return .drag(velocity: PetPoint(x: (last.point.x - first.point.x) / dt, y: (last.point.y - first.point.y) / dt))
    }
}

private func hypot(_ a: Double, _ b: Double) -> Double { (a * a + b * b).squareRoot() }
