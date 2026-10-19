/// Every animation the pet can play, with a duration for each frame. Key poses are held and
/// in-betweens are quick: anticipation and impact read better than with one even frame rate.
public enum PetState: String, CaseIterable, Codable, Sendable {
    case idle, hop, working, alert, celebrate, sleep, lowLimit, error, peek, dragged, drop, talk
    /// Home (notch or burrow) states: hidden with glowing eyes, peeking out to stay, diving back in.
    case burrowed, peekHold, dive
    /// Fidgets and reactions: a yawn and stretch, shy when fussed over, cross when clicked too much,
    /// a somersault for big finished tasks, a roll over its edge.
    case yawn, shy, angry, flip, tumble

    /// Seconds per frame. Built once: the frame clock reads it on every tick.
    public var durations: [Double] { Self.table[self]! }
    public var frameCount: Int { durations.count }
    public var totalDuration: Double { durations.reduce(0, +) }

    private static let table: [PetState: [Double]] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.millis.map { $0 / 1000 }) })

    private var millis: [Double] {
        switch self {
        case .idle:
            Self.repeating(10, 140) + [70, 55, 70] + Self.repeating(4, 140) + [400] + Self.repeating(4, 170) + [140, 140]
        case .hop: [110, 150, 110, 50, 40, 50, 120, 120, 50, 40, 110, 90, 80, 160]
        case .working: [90, 70, 90, 70, 110, 70, 90, 70, 300, 90, 70, 90]
        case .alert: [80, 80, 70, 60, 60, 70, 80, 120, 90, 90, 90, 90]
        case .celebrate: [140, 90, 60, 50, 50, 60, 90, 90, 60, 50, 50, 110, 90, 80, 160, 200]
        case .sleep: Self.repeating(8, 300) + [120, 400, 300, 300]
        case .lowLimit: Self.repeating(16, 100)
        case .error: Self.repeating(6, 70) + Self.repeating(10, 90)
        case .peek: Self.repeating(12, 83) + Self.repeating(10, 100) + Self.repeating(6, 70)
        case .dragged: Self.repeating(10, 100)
        case .drop: [40, 40, 40, 40, 90, 60, 60, 70, 70, 80, 90, 200]
        case .talk: Self.repeating(8, 100)
        case .burrowed: Self.repeating(16, 250)
        case .peekHold: Self.repeating(10, 125)
        case .dive: Self.repeating(6, 70)
        case .yawn: [400, 120, 120, 150, 700, 120, 90, 90, 160, 400]
        case .shy: [200, 150, 150, 150, 200, 250, 250, 300, 300, 400]
        case .angry: [120, 80, 120, 80, 120, 80, 200, 150, 150, 150, 300, 300]
        case .flip: [140, 90, 60, 50, 50, 50, 50, 50, 60, 80, 90, 140, 160, 200, 200, 300]
        case .tumble: [220, 80, 70, 70, 70, 90, 140, 220, 80, 70, 70, 70, 90, 140]
        }
    }

    private static func repeating(_ count: Int, _ ms: Double) -> [Double] { Array(repeating: ms, count: count) }

    /// One-shots play once and hand control back to the base state.
    public var loops: Bool {
        switch self {
        case .hop, .celebrate, .peek, .drop, .dive, .yawn, .shy, .angry, .flip, .tumble: false
        default: true
        }
    }
}
