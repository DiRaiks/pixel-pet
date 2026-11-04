/// Small value types so PetCore stays free of AppKit and CoreGraphics.
public struct PetPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct PetSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct PetRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(_ p: PetPoint) -> Bool {
        p.x >= x && p.x < maxX && p.y >= y && p.y < maxY
    }
}

/// Where a card goes next to the pet (AppKit coordinates, y up): above it when there's room, otherwise
/// below, centered on it. When neither fits, beside it on the side with more room, so the card never ends
/// up under the pet; a card that grows (a translation coming in) is placed again the same way.
public enum CardPlacement {
    public static let gap = 4.0
    public static let margin = 8.0

    public static func origin(for size: PetSize, near pet: PetRect, in area: PetRect, preferAbove: Bool = true) -> PetPoint {
        let x = clamp(pet.x + pet.width / 2 - size.width / 2, area.x + margin, area.maxX - size.width - margin)
        let above = pet.maxY + gap, below = pet.y - gap - size.height
        for y in preferAbove ? [above, below] : [below, above] where y >= area.y && y + size.height <= area.maxY {
            return PetPoint(x: x, y: y)
        }
        let roomRight = area.maxX - pet.maxX, roomLeft = pet.x - area.x
        let side = roomRight >= roomLeft ? pet.maxX + gap : pet.x - gap - size.width
        let y = clamp(pet.y + pet.height / 2 - size.height / 2, area.y, area.maxY - size.height)
        return PetPoint(x: clamp(side, area.x, area.maxX - size.width), y: y)
    }

    /// `lower` wins when the range is empty (a card larger than the area): it stays on screen's start.
    private static func clamp(_ v: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(v, upper))
    }
}
