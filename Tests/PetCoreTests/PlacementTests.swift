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

@Suite struct CardPlacementTests {
    let area = PetRect(x: 0, y: 0, width: 1440, height: 900)
    let card = PetSize(width: 360, height: 300)

    func overlaps(_ o: PetPoint, _ size: PetSize, _ pet: PetRect) -> Bool {
        o.x < pet.maxX && o.x + size.width > pet.x && o.y < pet.maxY && o.y + size.height > pet.y
    }

    /// Room above: above, centered on the pet.
    @Test func aboveWhenThereIsRoom() {
        let pet = PetRect(x: 600, y: 300, width: 128, height: 128)
        let o = CardPlacement.origin(for: card, near: pet, in: area)
        #expect(o == PetPoint(x: 484, y: 432))
    }

    /// The pet near the top (the case that hid the card's buttons): below it, never over it, also after
    /// the card grew and is placed again preferring the side it was on.
    @Test func belowWhenTheTopIsNear() {
        let pet = PetRect(x: 600, y: 700, width: 128, height: 128)
        for prefer in [true, false] {
            let o = CardPlacement.origin(for: card, near: pet, in: area, preferAbove: prefer)
            #expect(o.y + card.height <= pet.y)
            #expect(!overlaps(o, card, pet))
        }
    }

    /// A card that grew from below stays below while it fits there.
    @Test func keepsItsSideWhileItFits() {
        let pet = PetRect(x: 600, y: 500, width: 128, height: 128)
        let o = CardPlacement.origin(for: card, near: pet, in: area, preferAbove: false)
        #expect(o.y == 500 - CardPlacement.gap - card.height)
    }

    /// Too tall for either side: beside the pet, on the roomier side, still on screen and off the pet.
    @Test func besideWhenNeitherFits() {
        let tall = PetSize(width: 360, height: 600)
        let pet = PetRect(x: 300, y: 380, width: 128, height: 128)
        let o = CardPlacement.origin(for: tall, near: pet, in: area)
        #expect(o.x == pet.maxX + CardPlacement.gap)
        #expect(!overlaps(o, tall, pet))
        #expect(o.y >= area.y && o.y + tall.height <= area.maxY)
        let nearRight = PetRect(x: 1200, y: 380, width: 128, height: 128)
        let left = CardPlacement.origin(for: tall, near: nearRight, in: area)
        #expect(left.x + tall.width <= nearRight.x)
    }
}
