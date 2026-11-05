import Testing
import PetCore
@testable import PetSprites

/// Overlays and hats: nothing drawn on top of the body's outline or a hat, no hat cut off by the canvas,
/// and no jump of the body sideways when a state with an off-centre pose starts or ends.
@Suite struct OverlayTests {
    private let outline = Skin.lavender.outline

    private func frames(_ state: PetState, _ look: Look = .standard) -> [PixelCanvas] {
        SpriteFactory.frames(for: state, agentCubes: false, look: look)
    }

    private func count(_ f: PixelCanvas, _ color: RGBA) -> Int { f.pixels.filter { $0 == color }.count }

    /// Whether any pixel of `colors` sits next to (4-neighbour) a pixel of the body's outline.
    private func touchesOutline(_ f: PixelCanvas, _ colors: Set<RGBA>) -> Bool {
        (0..<f.height).contains { y in
            (0..<f.width).contains { x in
                guard let p = f.pixel(x, y), colors.contains(p) else { return false }
                return [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { f.pixel(x + $0.0, y + $0.1) == outline }
            }
        }
    }

    private func topRow(_ f: PixelCanvas, _ color: RGBA) -> Int? {
        (0..<f.height).first { y in (0..<f.width).contains { f.pixel($0, y) == color } }
    }

    private func leftmost(_ f: PixelCanvas) -> Int? {
        (0..<f.width).first { x in (0..<f.height).contains { f.pixel(x, $0) == outline } }
    }

    /// Jumps peak lower with a tall hat, so the hat stays whole on the canvas.
    @Test func jumpsKeepTheHatOnTheCanvas() {
        var party = Look.standard
        party.extras = [.partyHat]
        let looks: [(Look, Int)] = [(Look(accessory: .beanie), 5), (Look(accessory: .crown), 4),
                                    (Look(accessory: .propeller), 4), (party, 9)]
        for (look, height) in looks {
            for state in [PetState.hop, .celebrate, .drop] {
                for (i, f) in frames(state, look).enumerated() {
                    #expect((topRow(f, outline) ?? 99) >= height, "\(state) \(i) with \(look.accessory)")
                }
            }
        }
    }

    /// The tool bubble's tail leaves a hat alone.
    @Test func bubbleTailLeavesTheHat() {
        for (accessory, color) in [(Accessory.cap, Palette.capRed), (.crown, Palette.crownGold), (.beanie, Palette.beanie)] {
            let look = Look(accessory: accessory)
            let bare = count(frames(.idle, look)[0], color)
            #expect(count(frames(.breakHint, look)[0], color) == bare, "\(accessory)")
        }
    }

    /// The file about to be swallowed floats above a hat, not over it.
    @Test func swallowedFileFloatsAboveTheHat() {
        let look = Look(accessory: .propeller)
        #expect(count(frames(.swallow, look)[0], Palette.crownGold) == count(frames(.idle, look)[0], Palette.crownGold))
    }

    /// States that pose off-centre step there and back: the first and last frames are within 2 px of
    /// where the pet stands.
    @Test func offCentrePosesStepInAndOut() {
        let home = leftmost(frames(.idle)[0])!
        for state in [PetState.wave, .launch, .hookah, .hookahCloud, .tumble] {
            let f = frames(state)
            #expect(abs(leftmost(f.first!)! - home) <= 2, "\(state) start")
            #expect(abs(leftmost(f.last!)! - home) <= 2, "\(state) end")
        }
    }

    /// Stars, the anger mark, hearts and the sleep bubble keep a pixel of air from the outline.
    @Test func effectsKeepOffTheOutline() {
        let stars: Set<RGBA> = [Palette.amber, Palette.amberLight]
        for (i, f) in frames(.error).enumerated() where i >= 6 { #expect(!touchesOutline(f, stars), "error \(i)") }
        for (i, f) in frames(.dizzy).enumerated() { #expect(!touchesOutline(f, stars), "dizzy \(i)") }
        for (i, f) in frames(.angry).enumerated() { #expect(!touchesOutline(f, [Palette.errorFill]), "angry \(i)") }
        for (i, f) in frames(.purr).enumerated() { #expect(!touchesOutline(f, [Palette.heart, Palette.heartLight]), "purr \(i)") }
        for (i, f) in frames(.sleep).enumerated() { #expect(!touchesOutline(f, [Palette.bubble]), "sleep \(i)") }
    }
}
