/// Every animation the pet can play, with a duration for each frame. Key poses are held and
/// in-betweens are quick: anticipation and impact read better than with one even frame rate.
public enum PetState: String, CaseIterable, Codable, Sendable {
    case idle, hop, working, alert, celebrate, sleep, lowLimit, error, peek, dragged, drop, talk
    /// Home (notch or burrow) states: hidden with glowing eyes, peeking out to stay, diving back in.
    case burrowed, peekHold, dive
    /// Fidgets and reactions: a yawn and stretch, shy when fussed over, cross when clicked too much,
    /// a somersault for big finished tasks, a roll over its edge.
    case yawn, shy, angry, flip, tumble
    /// At the keyboard while agents work: a sip from the mug, a stretch, a pause to think, a burst of fast
    /// typing, and a look over at the agent blocks on either side.
    case workSip, workStretch, workThink, workRush, glanceLeft, glanceRight
    /// A hardware key wants a touch (GPG signing): holds up a little YubiKey with its pad blinking, then
    /// a happy check mark once touched.
    case touchKey, touchDone
    /// The same from home: out of the hole, key held under it.
    case touchKeyHome
    /// An agent waits for an answer rather than a permission: a "?" and a tilted head.
    case question
    /// Limits: the 5-hour window reset (refills from the bottom); a limit reached (lies spent, a clock above).
    case refill, exhausted
    /// Subagents: little copies pop out of the pet, and come back when they're done.
    case spawn, recall
    /// Claude compacts its context: squeezed like an accordion.
    case compact
    /// Battery: low and not charging (droopy, a red battery), and plugged in (a lightning bolt).
    case tired, plugIn
    /// Thrown hard: tumbles through the air; shaken while dragged: dizzy after.
    case thrown, dizzy
    /// Thrown into the side of the screen: flattened against it, slides down, peels off.
    case splatLeft, splatRight
    /// A break with a hookah when no agents work: a long draw, then smoke rings drifting up, or now and
    /// then one big cloud the pet vanishes into.
    case hookah, hookahCloud

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
        case .workSip: [180, 90, 90, 250, 500, 250, 90, 120, 500, 200]
        case .workStretch: [150, 90, 90, 500, 300, 90, 100, 90, 250, 200]
        case .workThink: [200, 150, 300, 300, 400, 300, 300, 250, 150, 350, 150, 150]
        case .workRush: Self.repeating(16, 50) + [250]
        case .glanceLeft, .glanceRight: [80, 600, 100, 300, 90, 300, 80, 120]
        case .touchKey, .touchKeyHome: Self.repeating(8, 150)
        case .touchDone: [90, 90, 90, 120, 150, 250, 300, 300]
        case .question: Self.repeating(8, 160) + [300, 300]
        case .refill: Self.repeating(8, 90) + [150, 200, 250, 300]
        case .exhausted: Self.repeating(8, 400)
        case .spawn: Self.repeating(8, 90) + [200, 250]
        case .recall: Self.repeating(6, 90) + [200, 250]
        case .compact: [60, 60, 80, 300, 80, 60, 100, 150]
        case .tired: Self.repeating(16, 220)
        case .plugIn: [80, 80, 100, 150, 200, 250, 250, 300]
        case .thrown: [50, 45, 45, 45, 45, 45, 45, 60]
        case .splatLeft, .splatRight: [60, 80, 150, 120, 120, 100, 100, 90, 90, 150]
        case .hookah, .hookahCloud: [300, 250, 250, 300, 500, 250] + Self.repeating(8, 220) + [400, 500]
        case .dizzy: Self.repeating(6, 90) + Self.repeating(8, 120)
        }
    }

    private static func repeating(_ count: Int, _ ms: Double) -> [Double] { Array(repeating: ms, count: count) }

    /// One-shots play once and hand control back to the base state.
    public var loops: Bool {
        switch self {
        case .hop, .celebrate, .peek, .drop, .dive, .yawn, .shy, .angry, .flip, .tumble,
             .workSip, .workStretch, .workThink, .workRush, .glanceLeft, .glanceRight, .touchDone,
             .refill, .spawn, .recall, .compact, .plugIn, .thrown, .dizzy, .splatLeft, .splatRight, .hookah, .hookahCloud: false
        default: true
        }
    }
}
