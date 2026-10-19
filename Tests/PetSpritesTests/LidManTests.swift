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

    /// "!" steps aside so the diamond stays visible.
    @Test func alertMarkClearsTheDiamond() {
        let frame = SpriteFactory.frame(for: .alert, index: 0, agentCubes: false, look: lm)
        let amber = (0..<32).flatMap { y in (0..<32).filter { frame.pixel($0, y) == Palette.amber }.map { ($0, y) } }
        #expect(!amber.isEmpty)
        #expect(amber.allSatisfy { $0.0 >= 18 })
    }
}
