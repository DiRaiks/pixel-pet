/// Where the pet lives when it isn't on the desk: the MacBook notch, or a small "burrow" drawn at the
/// top center of a screen without one.
public struct HomeSpot: Equatable, Sendable {
    /// Top-center point of the home, on the screen's top edge.
    public var anchor: PetPoint
    public var hasNotch: Bool
    /// Height of the hardware notch; the pet hangs lower so its eyes aren't lost inside the cut-out.
    public var notchHeight: Double
    /// Horizontal extent of the screen's top edge: dropped anywhere along it, the pet goes to this home.
    public var edge: ClosedRange<Double>?
    public init(anchor: PetPoint, hasNotch: Bool, notchHeight: Double = 0, edge: ClosedRange<Double>? = nil) {
        self.anchor = anchor
        self.hasNotch = hasNotch
        self.notchHeight = notchHeight
        self.edge = edge
    }
}

public enum HomeGeometry {
    /// Dropping the pet with its top-center this close to a home pulls it in.
    public static let snapRadius = 90.0
    /// Pulled out of a home, it only goes back when let go about where it sat: with the full snap radius
    /// a short tug downward would land it right back inside, and the pet would seem stuck there.
    public static let releaseRadius = 24.0
    /// Let go with its top this close below the top edge of a screen (or above it), anywhere along it, the pet goes home there:
    /// aiming for the exact middle of the edge is too fiddly.
    public static let edgeBand = 60.0

    public static func home(on screen: PetScreen, notch: PetRect?) -> HomeSpot {
        let x = notch.map { $0.x + $0.width / 2 } ?? (screen.frame.x + screen.frame.width / 2)
        return HomeSpot(anchor: PetPoint(x: x, y: screen.frame.maxY), hasNotch: notch != nil, notchHeight: notch?.height ?? 0,
                        edge: screen.frame.x...screen.frame.maxX)
    }

    /// The pet's window hangs from the top edge, centered on the home. Under a notch it drops so the eyes
    /// (one sprite pixel below the top) sit right at the notch's lower edge and the drawn hole extends it.
    public static func windowOrigin(for home: HomeSpot, size: PetSize) -> PetPoint {
        let pixel = size.width / 32
        let drop = home.notchHeight > 0 ? home.notchHeight - pixel : 0
        return PetPoint(x: home.anchor.x - size.width / 2, y: home.anchor.y - size.height - drop)
    }

    /// The notch is the gap between the two menu-bar areas beside it. Their coordinate space isn't
    /// documented as global, so areas that don't lie on the screen are treated as screen-local.
    public static func notch(screen: PetRect, left: PetRect?, right: PetRect?, safeTop: Double) -> PetRect? {
        guard safeTop > 0, var l = left, var r = right else { return nil }
        let onScreen = l.x >= screen.x - 0.5 && r.maxX <= screen.maxX + 0.5
        if !onScreen {
            l.x += screen.x; r.x += screen.x
            l.y += screen.y; r.y += screen.y
        }
        guard r.x > l.maxX else { return nil }
        return PetRect(x: l.maxX, y: l.y, width: r.x - l.maxX, height: l.height)
    }

    /// Near a home's anchor (`snapRadius`) or anywhere along its screen's top edge (`edgeBand`) pulls the pet in.
    /// `leaving` is the home the drag started from: it takes the pet back only within `releaseRadius` of its
    /// seat; every other home keeps the full snap radius.
    public static func snapTarget(windowOrigin origin: PetPoint, size: PetSize, homes: [HomeSpot],
                                  leaving: HomeSpot? = nil) -> HomeSpot? {
        let top = PetPoint(x: origin.x + size.width / 2, y: origin.y + size.height)
        func distance(_ h: HomeSpot) -> Double {
            let dx = h.anchor.x - top.x, dy = h.anchor.y - top.y
            return (dx * dx + dy * dy).squareRoot()
        }
        func takesBack(_ h: HomeSpot) -> Bool {
            guard h == leaving else { return distance(h) <= snapRadius || onEdge(h) }
            let seat = windowOrigin(for: h, size: size)
            let dx = seat.x - origin.x, dy = seat.y - origin.y
            return (dx * dx + dy * dy).squareRoot() <= releaseRadius
        }
        // The cursor stops at the top of the screen while the pet is held by its middle, so at release the
        // window usually pokes well above the edge: everything from just below it up to a window's height counts.
        func onEdge(_ h: HomeSpot) -> Bool {
            guard let edge = h.edge, edge.contains(top.x) else { return false }
            return top.y >= h.anchor.y - edgeBand && top.y <= h.anchor.y + size.height
        }
        return homes.filter(takesBack).min { distance($0) < distance($1) }
    }
}
