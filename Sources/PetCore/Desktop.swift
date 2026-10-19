import Foundation

/// Where the pet's eyes point, in sprite pixels: x -1...1, y -1 (up) or 0.
public struct Gaze: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The cursor only draws the eyes when it's near; far away the pet keeps its own glances.
    public static let radius = 300.0
    static let deadZone = 40.0

    /// Points are AppKit screen coordinates (y up). There's no "look down" pose, so below stays level.
    public static func toward(_ target: PetPoint, from pet: PetPoint, radius: Double = Gaze.radius) -> Gaze? {
        let dx = target.x - pet.x, dy = target.y - pet.y
        guard (dx * dx + dy * dy).squareRoot() <= radius else { return nil }
        return Gaze(x: dx > deadZone ? 1 : dx < -deadZone ? -1 : 0, y: dy > deadZone ? -1 : 0)
    }
}

/// Lets one reaction through per interval; frequent events must stay subtle.
public struct ReactionThrottle: Sendable {
    public let interval: TimeInterval
    private var last: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public mutating func take(at now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}

public enum Fullscreen {
    /// A window filling the whole screen (not just the visible area under the menu bar and Dock).
    public static func covers(window: PetRect, screen: PetRect, tolerance: Double = 2) -> Bool {
        window.x <= screen.x + tolerance && window.y <= screen.y + tolerance
            && window.maxX >= screen.maxX - tolerance && window.maxY >= screen.maxY - tolerance
    }

    /// CGWindowList bounds are top-left based on the primary screen; AppKit is bottom-left.
    public static func appKitRect(cg: PetRect, primaryHeight: Double) -> PetRect {
        PetRect(x: cg.x, y: primaryHeight - cg.y - cg.height, width: cg.width, height: cg.height)
    }
}
