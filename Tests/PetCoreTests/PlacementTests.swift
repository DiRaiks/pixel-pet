import Testing
@testable import PetCore

@Suite struct PlacementTests {
    // Primary 2560x1440 with menu bar (25) on top and Dock (60) at the bottom.
    let main = PetScreen(frame: PetRect(x: 0, y: 0, width: 2560, height: 1440),
                         visible: PetRect(x: 0, y: 60, width: 2560, height: 1355))
    // Secondary to the right, shifted down (negative y), no Dock.
    let right = PetScreen(frame: PetRect(x: 2560, y: -196, width: 1920, height: 1080),
                          visible: PetRect(x: 2560, y: -196, width: 1920, height: 1055))
    // Secondary to the left at negative x.
    let left = PetScreen(frame: PetRect(x: -1920, y: 0, width: 1920, height: 1080),
                         visible: PetRect(x: -1920, y: 0, width: 1920, height: 1055))
    let size = PetSize(width: 128, height: 128)

    @Test func keepsSavedOriginWhenFullyVisible() {
        let saved = PetPoint(x: 3000, y: 100)
        #expect(Placement.resolve(saved: saved, size: size, screens: [main, right]) == saved)
    }

    @Test func savedOriginUnderTheDockIsClampedNotReset() {
        // Dock grew after the pet was parked at the bottom: stay on this screen, just above the Dock.
        let saved = PetPoint(x: 500, y: 0)
        #expect(Placement.resolve(saved: saved, size: size, screens: [main, right]) == PetPoint(x: 500, y: 60))
    }

    @Test func overhangingOriginIsPulledInside() {
        // Above the right screen's top edge (y 884), so only the main screen overlaps.
        let saved = PetPoint(x: 2500, y: 1000)
        #expect(Placement.resolve(saved: saved, size: size, screens: [main, right]) == PetPoint(x: 2560 - 128, y: 1000))
    }

    @Test func savedOnLeftScreenAtNegativeX() {
        let saved = PetPoint(x: -1000, y: 300)
        #expect(Placement.resolve(saved: saved, size: size, screens: [main, left]) == saved)
    }

    @Test func fallsBackToBottomRightOfFirstScreenWhenDisconnected() {
        let origin = Placement.resolve(saved: PetPoint(x: 9000, y: 9000), size: size, screens: [main, right])
        #expect(origin == PetPoint(x: 2560 - 128 - Placement.margin, y: 60 + Placement.margin))
    }

    @Test func fallsBackWhenNothingSaved() {
        let origin = Placement.resolve(saved: nil, size: size, screens: [main])
        #expect(origin == PetPoint(x: 2560 - 128 - Placement.margin, y: 60 + Placement.margin))
    }

    @Test func bestScreenPicksLargestOverlap() {
        // Mostly on the right screen, a sliver on the main one.
        #expect(Placement.bestScreen(for: PetPoint(x: 2540, y: 100), size: size, screens: [main, right]) == right)
        #expect(Placement.bestScreen(for: PetPoint(x: 9000, y: 100), size: size, screens: [main, right]) == nil)
    }

    @Test func clampOnNegativeOriginScreen() {
        #expect(Placement.clamp(PetPoint(x: -2000, y: -50), size: size, in: left.visible) == PetPoint(x: -1920, y: 0))
    }

    @Test func flickTravelsWithVelocityAndStaysOnScreen() {
        let start = PetPoint(x: 1000, y: 500)
        #expect(Placement.flickDestination(from: start, velocity: PetPoint(x: 1000, y: 0), size: size, screens: [main])
            == PetPoint(x: 1000 + 1000 * Placement.throwTime, y: 500))
        #expect(Placement.flickDestination(from: start, velocity: PetPoint(x: 0, y: -99_999), size: size, screens: [main])
            == PetPoint(x: 1000, y: 60))
    }

    @Test func flickFromGapBetweenScreensLandsOnNearestOverlap() {
        let start = PetPoint(x: 2500, y: 1400)
        let landed = Placement.flickDestination(from: start, velocity: PetPoint(x: 0, y: 0), size: size, screens: [main, right])
        #expect(landed == PetPoint(x: 2560 - 128, y: 1415 - 128))
    }
}
