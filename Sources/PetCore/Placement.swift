/// A display: its full frame and the part not covered by the menu bar and Dock.
public struct PetScreen: Equatable, Sendable {
    public var frame: PetRect
    public var visible: PetRect
    public init(frame: PetRect, visible: PetRect) { self.frame = frame; self.visible = visible }
}

/// Where the pet window goes and how it stays on screen. Bottom-left origin, like AppKit.
public enum Placement {
    public static let margin = 24.0
    /// How far a flick carries the pet: release velocity times this many seconds.
    public static let throwTime = 0.12

    /// The screen whose full frame overlaps the pet most; nil when it is off every screen.
    /// Full frames (not visibleFrame) so a pet parked over a grown Dock still belongs to its screen.
    public static func bestScreen(for origin: PetPoint, size: PetSize, screens: [PetScreen]) -> PetScreen? {
        let pet = PetRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        let scored = screens.map { ($0, pet.overlapArea(with: $0.frame)) }.filter { $0.1 > 0 }
        return scored.max { $0.1 < $1.1 }?.0
    }

    public static func resolve(saved: PetPoint?, size: PetSize, screens: [PetScreen]) -> PetPoint {
        if let saved, let screen = bestScreen(for: saved, size: size, screens: screens) {
            return clamp(saved, size: size, in: screen.visible)
        }
        guard let first = screens.first?.visible else { return PetPoint(x: margin, y: margin) }
        return PetPoint(x: first.maxX - size.width - margin, y: first.y + margin)
    }

    public static func clamp(_ origin: PetPoint, size: PetSize, in area: PetRect) -> PetPoint {
        PetPoint(
            x: min(max(origin.x, area.x), area.maxX - size.width),
            y: min(max(origin.y, area.y), area.maxY - size.height)
        )
    }

    public static func flickDestination(from origin: PetPoint, velocity: PetPoint, size: PetSize,
                                        screens: [PetScreen]) -> PetPoint {
        let target = PetPoint(x: origin.x + velocity.x * throwTime, y: origin.y + velocity.y * throwTime)
        guard let screen = bestScreen(for: origin, size: size, screens: screens) ?? screens.first else { return target }
        return clamp(target, size: size, in: screen.visible)
    }
}

extension PetRect {
    func overlapArea(with other: PetRect) -> Double {
        let w = min(maxX, other.maxX) - max(x, other.x)
        let h = min(maxY, other.maxY) - max(y, other.y)
        return w > 0 && h > 0 ? w * h : 0
    }
}

/// Maps a point in the pet view (bottom-left origin, points) to a sprite pixel (top-left origin).
public enum SpriteHit {
    public struct Pixel: Equatable, Sendable {
        public let x: Int
        public let y: Int
    }

    public static func pixel(x: Double, y: Double, scale: Double, height: Int) -> Pixel {
        Pixel(x: Int((x / scale).rounded(.down)), y: height - 1 - Int((y / scale).rounded(.down)))
    }
}
