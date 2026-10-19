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

    public init(start: PetPoint, time: Double) {
        self.start = start
        samples = [(start, time)]
    }

    public mutating func move(to point: PetPoint, time: Double) {
        samples.append((point, time))
        samples.removeAll { time - $0.time > Self.velocityWindow * 2 }
        if !isDragging, hypot(point.x - start.x, point.y - start.y) >= Self.threshold {
            isDragging = true
        }
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
