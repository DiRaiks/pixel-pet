import Testing
import PetCore
@testable import PetSprites

/// A new version as a box with the update arrow: arriving, waiting, unpacked, and the pop after the restart.
@Suite struct UpdateSpritesTests {
    let looks = [Look.standard, Look(figure: .lidman), Look(figure: .clip)]
    let states: [PetState] = [.updateArrive, .updateWait, .updateUnpack, .updateDone]

    func has(_ f: PixelCanvas, _ color: RGBA) -> Bool { f.pixels.contains(color) }

    /// Waiting, the box and its arrow stand by the pet, the arrow glowing now and then.
    @Test func waitingShowsTheBoxAndItsArrow() {
        for look in looks {
            let frames = SpriteFactory.frames(for: .updateWait, agentCubes: false, look: look)
            #expect(frames.allSatisfy { has($0, SpriteFactory.kraft) }, "\(look.figure)")
            #expect(frames.contains { has($0, Palette.teal) } && frames.contains { has($0, Palette.tealLight) }, "\(look.figure)")
        }
    }

    /// The box floats down on a balloon that lets go once it lands.
    @Test func arrivesOnABalloon() {
        let frames = SpriteFactory.frames(for: .updateArrive, agentCubes: false)
        #expect(has(frames[8], SpriteFactory.balloon))
        #expect(!has(frames[frames.count - 1], SpriteFactory.balloon))
    }

    /// After the restart the pet starts inside the closed box (none of it below the box) and ends out of it,
    /// with the box gone and a check mark over it.
    @Test func popsOutOfTheBox() {
        let frames = SpriteFactory.frames(for: .updateDone, agentCubes: false)
        #expect(!(27..<32).contains { y in (0..<32).contains { frames[0].pixel($0, y) == Skin.lavender.outline } })
        let last = frames[frames.count - 1]
        #expect(!has(last, SpriteFactory.kraft))
        #expect(has(last, Palette.teal))
        #expect(has(last, Skin.lavender.fill))
    }

    /// Columns 0-4 and 27-31 below row 8 belong to the agent blocks.
    @Test func keepsClearOfTheAgentColumns() {
        for look in looks {
            for state in states {
                for (i, f) in SpriteFactory.frames(for: state, agentCubes: false, look: look).enumerated() {
                    for y in 8..<32 {
                        for x in [0, 1, 2, 3, 4, 27, 28, 29, 30, 31] where f.pixel(x, y) != nil {
                            Issue.record("\(look.figure) \(state) frame \(i) draws at \(x),\(y)")
                        }
                    }
                }
            }
        }
    }
}
