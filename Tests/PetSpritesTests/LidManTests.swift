import Foundation
import Testing
import PetCore
@testable import PetSprites

@Suite struct LidManTests {
    let lm = Look(figure: .lidman)

    /// LM wears his own aqua and nothing on his diamond, whatever the color and accessory settings say.
    @Test func keepsHisOwnColorsAndNoAccessory() {
        let look = Look(skin: .peach, accessory: .crown, figure: .lidman)
        #expect(look.skin == .lidman)
        #expect(look.accessory == .none)
        #expect(Look(skin: .peach, accessory: .crown).figure == .cube)
    }

    @Test func resolvesTheFigureSetting() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Look.resolve(skin: "mint", accessory: "cap", figure: "lidman", on: date) == lm)
        #expect(Look.resolve(skin: "mint", accessory: "cap", figure: "nonsense", on: date).figure == .cube)
        #expect(Look.resolve(skin: "mint", accessory: "cap", on: date).skin == .mint)
    }

    /// The diamond rises above where the cube's top would be, light on the left and dark on the right.
    @Test func idleHasTheDiamondAboveTheBody() {
        let frame = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: lm)
        let diamondRows = 0..<12
        let pixels = diamondRows.flatMap { y in (0..<32).compactMap { frame.pixel($0, y) } }
        #expect(pixels.contains(Palette.crystalLight))
        #expect(pixels.contains(Palette.crystalDark))
        #expect(frame.pixels.contains(Skin.lidman.fill))
    }

    /// Every frame of every state shows his body, including the square, squashed and tall ones
    /// (a square frame once collapsed the V cut and left only the face).
    @Test(arguments: PetState.allCases)
    func everyFrameHasABody(state: PetState) {
        for (i, frame) in SpriteFactory.frames(for: state, look: lm).enumerated() {
            #expect(frame.opaquePixelCount > 100, "\(state) frame \(i) looks empty")
            // Inside the notch hole he is (partly) out of sight, and an error turns him red.
            guard ![.burrowed, .peek, .dive, .error].contains(state) else { continue }
            #expect(frame.pixels.contains(Skin.lidman.outline), "\(state) frame \(i) has no outline")
        }
    }

    /// Jumps and stretches squash the diamond to the rows above the body instead of cutting its tip off at
    /// the top of the canvas. Turning frames swing it around and may graze an edge, so they're left out.
    @Test(arguments: PetState.allCases.filter { ![.flip, .tumble, .thrown].contains($0) })
    func diamondIsNeverCutOffAtTheTop(state: PetState) {
        for (i, frame) in SpriteFactory.frames(for: state, look: lm).enumerated() {
            let top = (0..<32).compactMap { frame.pixel($0, 0) }
            #expect(!top.contains(Palette.crystalLight) && !top.contains(Palette.crystalDark),
                    "\(state) frame \(i) cuts the diamond")
        }
    }

    /// Turned frames redraw the same big-eyed face upright.
    @Test func rotatedFramesKeepTheBigEyes() {
        var s = BodyStyle(look: lm)
        s.rotation = 30
        var c = PixelCanvas()
        c.body(s)
        #expect(c.pixels.contains(Palette.white))
    }

    /// The pupils follow the gaze both ways (they used to stay on the right whatever the cursor did).
    @Test func pupilsFollowTheGaze() {
        func pupilsX(_ x: Int) -> Int {
            let f = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, gaze: Gaze(x: x, y: 0), look: lm)
            // Only the eye rows (body top 12, eyes from row 17), so the smile below doesn't count.
            return (0..<32).filter { px in (17..<21).contains { f.pixel(px, $0) == Skin.lidman.eye } }.min()!
        }
        #expect(pupilsX(-1) + 2 < pupilsX(1))
        #expect(pupilsX(-1) < pupilsX(0) && pupilsX(0) < pupilsX(1))
    }

    /// A drop falls onto the diamond, splashes, and leaves two little puddles on the floor that dry up.
    @Test func dripFallsSplashesAndPuddles() {
        let frames = SpriteFactory.frames(for: .drip, look: lm)
        func water(_ f: PixelCanvas, rows: Range<Int>) -> Bool {
            rows.contains { y in (0..<32).contains { f.pixel($0, y) == Palette.water } }
        }
        #expect(water(frames[2], rows: 0..<4))
        #expect(!water(frames[0], rows: 0..<32))
        #expect(water(frames[8], rows: 27..<28))
        #expect(!water(frames[11], rows: 0..<32))
    }

    /// Melting, he lies flat for a while, then gathers up into a tall drop before settling back.
    @Test func meltSpreadsLowThenStretchesUp() {
        let frames = SpriteFactory.frames(for: .melt, look: lm)
        func top(_ f: PixelCanvas) -> Int { (0..<32).first { y in (0..<32).contains { f.pixel($0, y) != nil } }! }
        #expect(top(frames[5]) > top(frames[0]) + 8)
        #expect(top(frames[9]) < top(frames[0]))
        // As a puddle the face stays inside the body: nothing dark on the floor rows.
        for (i, f) in frames.enumerated() {
            #expect(!(26..<32).contains { y in (0..<32).contains { f.pixel($0, y) == Skin.lidman.eye } }, "frame \(i)")
        }
    }

    /// The cube has no diamond to drip on: played from the State menu it just stands there, no water.
    @Test func cubeDoesNotDripOrMelt() {
        for state in [PetState.drip, .melt] {
            for f in SpriteFactory.frames(for: state, agentCubes: false) {
                #expect(!f.pixels.contains(Palette.water))
                #expect(f == SpriteFactory.frames(for: state, agentCubes: false)[0])
            }
        }
    }

    /// Out of the home hole LM peeks 2 rows less than the cube, and the room his diamond needs on the desk
    /// doesn't push him down there (that once showed the V of his top as two ears).
    @Test func peeksOutLessThanTheCube() {
        func bottom(_ f: PixelCanvas) -> Int { (0..<32).last { y in (0..<32).contains { f.pixel($0, y) != nil } }! }
        for state in [PetState.peekHold, .peek] {
            for (i, (lm, cube)) in zip(SpriteFactory.frames(for: state, agentCubes: false, look: lm),
                                       SpriteFactory.frames(for: state, agentCubes: false)).enumerated() {
                // Frames where the cube is still all inside the hole (rows 0-5) look the same for both.
                guard bottom(cube) > 5 else { continue }
                #expect(bottom(lm) == max(5, bottom(cube) - SpriteFactory.lidManPeekRaise), "\(state) frame \(i)")
            }
        }
    }

    /// "!" steps aside so the diamond stays visible.
    @Test func alertMarkClearsTheDiamond() {
        let frame = SpriteFactory.frame(for: .alert, index: 0, agentCubes: false, look: lm)
        let amber = (0..<32).flatMap { y in (0..<32).filter { frame.pixel($0, y) == Palette.amber }.map { ($0, y) } }
        #expect(!amber.isEmpty)
        #expect(amber.allSatisfy { $0.0 >= 18 })
    }
}
