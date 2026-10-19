/// Every animation the pet can play. Frame counts and rates mirror docs/prototype/sprites.html.
public enum PetState: String, CaseIterable, Codable, Sendable {
    case idle, hop, working, alert, celebrate, sleep, lowLimit, error, peek, dragged, drop, talk
    /// Home (notch or burrow) states: hidden with glowing eyes, peeking out to stay, diving back in.
    case burrowed, peekHold, dive

    public var frameCount: Int {
        switch self {
        case .idle, .sleep: 24
        case .hop: 14
        case .working, .alert, .error: 12
        case .celebrate, .lowLimit: 16
        case .peek: 28
        case .dragged: 10
        case .drop: 6
        case .talk: 8
        case .burrowed: 16
        case .peekHold: 10
        case .dive: 6
        }
    }

    public var fps: Double {
        switch self {
        case .idle: 8
        case .hop, .error: 14
        case .working, .lowLimit, .dragged, .drop, .talk: 10
        case .alert, .celebrate, .peek: 12
        case .sleep: 6
        // Always on screen at home, so the cheapest loop: 4 fps is enough for glances and blinks.
        case .burrowed: 4
        case .peekHold: 8
        case .dive: 14
        }
    }

    /// One-shot states play once and hand control back to the base state.
    public var loops: Bool {
        switch self {
        case .hop, .celebrate, .peek, .drop, .dive: false
        default: true
        }
    }
}
