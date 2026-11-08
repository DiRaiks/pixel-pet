import Foundation
import Testing
import PetCore
@testable import PetSprites

@Suite struct ClipTests {
    let clip = Look(figure: .clip)

    /// The paperclip takes the color setting like the cube, but wears no accessory on its loop.
    @Test func takesTheColorButNoAccessory() {
        let look = Look(skin: .mint, accessory: .crown, figure: .clip)
        #expect(look.skin == .mint)
        #expect(look.accessory == .none)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let resolved = Look.resolve(skin: "peach", accessory: "cap", figure: "clip", on: date)
        #expect(resolved.figure == .clip && resolved.skin == .peach && resolved.accessory == .none)
    }

    /// Idle, the top loop rises above where the cube's top would be (row 12), in the skin's wire colors.
    @Test func idleHasTheLoopAboveTheBox() {
        let frame = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: clip)
        let above = (4..<12).flatMap { y in (0..<32).compactMap { frame.pixel($0, y) } }
        #expect(above.contains(Skin.lavender.outline))
        #expect(above.contains(Skin.lavender.highlight))
        #expect(frame.pixels.contains(Palette.white), "eyes")
    }

    /// Every frame of every state shows the wire.
    @Test(arguments: PetState.allCases)
    func everyFrameHasTheWire(state: PetState) {
        for (i, frame) in SpriteFactory.frames(for: state, look: clip).enumerated() {
            #expect(frame.opaquePixelCount > 60, "\(state) frame \(i) looks empty")
            // Inside the notch hole it is (partly) out of sight, and an error turns it red.
            guard ![.burrowed, .peek, .dive, .error].contains(state) else { continue }
            if state == .screenshot, i == 2 { continue }
            #expect(frame.pixels.contains(Skin.lavender.outline), "\(state) frame \(i) has no outline")
        }
    }

    /// Jumps squash the loop to the rows above the box instead of cutting it off at the top of the canvas.
    /// Turning frames swing it around, and hanging from the home hole the top is inside the hole.
    @Test(arguments: PetState.allCases.filter { ![.flip, .tumble, .thrown, .peek, .peekHold, .dive, .burrowed,
                                                   .touchKeyHome].contains($0) })
    func loopIsNeverCutOffAtTheTop(state: PetState) {
        for (i, frame) in SpriteFactory.frames(for: state, look: clip).enumerated() {
            let top = (0..<32).compactMap { frame.pixel($0, 0) }
            #expect(!top.contains(Skin.lavender.highlight), "\(state) frame \(i) cuts the loop")
        }
    }

    /// With no limit to show, the loop keeps its color: rows above the box once counted as drained.
    @Test func loopIsNotDrainedWithoutALimit() {
        let frame = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: clip)
        let loop = (0..<12).flatMap { y in (0..<32).compactMap { frame.pixel($0, y) } }
        #expect(!loop.contains(Skin.lavender.empty))
    }

    /// The night skin's face color is light; on the white of the eyes the pupils take its dark fill instead.
    @Test func nightPupilsAreDark() {
        let frame = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: Look(skin: .night, figure: .clip))
        #expect(frame.pixels.contains(Skin.night.fill))
    }

    /// The pupils follow the gaze both ways.
    @Test func pupilsFollowTheGaze() {
        func pupilsX(_ x: Int) -> Int {
            let f = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, gaze: Gaze(x: x, y: 0), look: clip)
            return (0..<32).filter { px in (0..<14).contains { f.pixel(px, $0) == Skin.lavender.eye } }.min()!
        }
        #expect(pupilsX(-1) < pupilsX(0) && pupilsX(0) < pupilsX(1))
    }

    /// Its eyes sit up on the loop, so out of the home hole it hangs further down than the cube: the eyes
    /// clear the hole.
    @Test func peeksOutWithItsEyesShowing() {
        let frame = SpriteFactory.frame(for: .peekHold, index: 0, agentCubes: false, look: clip)
        #expect(frame.pixels.contains(Palette.white))
        #expect(frame.pixels.contains(Skin.lavender.eye))
    }

    /// Turned frames redraw the round eyes upright.
    @Test func rotatedFramesKeepTheEyes() {
        var s = BodyStyle(look: clip)
        s.rotation = 30
        var c = PixelCanvas()
        c.body(s)
        #expect(c.pixels.contains(Palette.white))
    }

    /// Sleeping, the nightcap sits on the loop; typing for long, the headband wraps it.
    @Test func wearsTheNightcapAndHeadband() {
        let sleep = SpriteFactory.frame(for: .sleep, index: 0, agentCubes: false, look: clip)
        #expect(sleep.pixels.contains(Palette.capRed))
        let work = SpriteFactory.frame(for: .working, index: 0, agentCubes: false, look: clip, props: .headband)
        #expect(work.pixels.contains(Palette.capRed))
    }
}
