import Testing
import PetCore
@testable import PetSprites

/// Small icons that have to read at 64 pt: kept apart from the body's outline and from each other.
@Suite struct IconTests {
    private func frames(_ state: PetState) -> [PixelCanvas] { SpriteFactory.frames(for: state, agentCubes: false) }

    private func touches(_ f: PixelCanvas, _ a: RGBA, _ b: RGBA) -> Bool {
        (0..<f.height).contains { y in
            (0..<f.width).contains { x in
                f.pixel(x, y) == a && [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { f.pixel(x + $0.0, y + $0.1) == b }
            }
        }
    }

    private func firstPixel(_ f: PixelCanvas, _ color: RGBA) -> (Int, Int)? {
        for y in 0..<f.height { for x in 0..<f.width where f.pixel(x, y) == color { return (x, y) } }
        return nil
    }

    /// The alarm clock's bells stay off the top edge of the canvas.
    @Test func clockStaysOnTheCanvas() {
        for state in [PetState.meetingSoon, .meetingNow] {
            for f in frames(state) { #expect((0..<f.width).allSatisfy { f.pixel($0, 0) == nil }, "\(state)") }
        }
    }

    /// The recording dot sits apart from the microphone.
    @Test func recordingDotIsApartFromTheMic() {
        for f in frames(.onAir) { #expect(!touches(f, Palette.rec, Palette.keyboard)) }
    }

    /// The black key never touches the pet's dark outline.
    @Test func keyIsApartFromTheOutline() {
        for f in frames(.touchKey) { #expect(!touches(f, Palette.keyBody, Skin.lavender.outline)) }
    }

    /// A status battery is in one place, whether it's low power or a low battery.
    @Test func batteryHasOneSpot() {
        let low = firstPixel(frames(.lowPower)[0], Palette.accessoryDark)
        let tired = firstPixel(frames(.tired)[0], Palette.accessoryDark)
        #expect(low != nil && low! == tired!)
        #expect(low! == (SpriteFactory.batterySpot.x, SpriteFactory.batterySpot.y))
    }
}
