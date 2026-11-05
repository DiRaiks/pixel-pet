import Foundation

/// The text heard so far: settled pieces joined up, plus the guess for what's being said right now, which
/// the recognizer keeps revising until it settles too.
public struct Transcript: Equatable, Sendable {
    public private(set) var settled = ""
    public private(set) var pending = ""

    public init() {}

    /// Everything so far, the pending guess included.
    public var text: String { Self.join(settled, pending) }

    public mutating func apply(_ piece: String, final: Bool) {
        if final {
            settled = Self.join(settled, piece)
            pending = ""
        } else {
            pending = piece
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines), b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}
