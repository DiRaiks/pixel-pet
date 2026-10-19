/// Every animation the pet can play. Frame counts and rates mirror docs/prototype/sprites.html.
public enum PetState: String, CaseIterable, Codable, Sendable {
    case idle, hop, working, alert, celebrate, sleep, lowLimit, error, peek, dragged, drop, talk

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
        }
    }

    public var fps: Double {
        switch self {
        case .idle: 8
        case .hop, .error: 14
        case .working, .lowLimit, .dragged, .drop, .talk: 10
        case .alert, .celebrate, .peek: 12
        case .sleep: 6
        }
    }

    /// One-shot states play once and hand control back to the base state.
    public var loops: Bool {
        switch self {
        case .hop, .celebrate, .peek, .drop: false
        default: true
        }
    }
}
