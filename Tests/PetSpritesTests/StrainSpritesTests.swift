import Testing
import PetCore
@testable import PetSprites

/// Typing with more agents at once (`WorkProps.strain`).
@Suite struct StrainSpritesTests {
    func frames(_ level: Int, look: Look = .standard) -> [PixelCanvas] {
        SpriteFactory.frames(for: .working, agentCubes: false, look: look, props: .strain(level))
    }

    func count(_ frames: [PixelCanvas], _ color: RGBA) -> Int {
        frames.reduce(0) { $0 + $1.pixels.filter { $0 == color }.count }
    }

    @Test func levelRoundTripsAndClamps() {
        #expect((0...3).map { WorkProps.strain($0).strain } == [0, 1, 2, 3])
        #expect(WorkProps.strain(7).strain == 3)
        #expect(WorkProps.strain(0).isEmpty)
        // Doesn't spill into the other props.
        #expect(WorkProps.strain(3).intersection([.mug, .headband, .candle, .lamp]).isEmpty)
    }

    /// Level 0 is the ordinary typing loop, frame for frame.
    @Test func noStrainIsPlainTyping() {
        #expect(frames(0) == SpriteFactory.frames(for: .working, agentCubes: false))
    }

    /// More keys light at once with each step.
    @Test func moreKeysWithMoreAgents() {
        let lit = (0...2).map { count(frames($0), Palette.tealLight) }
        #expect(lit[0] < lit[1] && lit[1] < lit[2])
    }

    /// Sweat from 2 agents, on both sides from 4; none for one agent.
    @Test func sweatsFromTwoAgents() {
        #expect(count(frames(0), Palette.sweat) == 0)
        #expect(count(frames(1), Palette.sweat) > 0)
        #expect(count(frames(2), Palette.sweat) > count(frames(1), Palette.sweat))
    }

    /// Steam and sparks only at the top step, for every figure, never above the canvas.
    @Test func steamAndSparksAtTheTop() {
        for look in [Look.standard, Look(figure: .lidman), Look(figure: .clip)] {
            #expect(count(frames(2, look: look), Palette.amber) == 0, "\(look.figure)")
            #expect(count(frames(3, look: look), Palette.amber) > 0, "\(look.figure) sparks")
            #expect(count(frames(3, look: look), Palette.steam) > 0, "\(look.figure) steam")
        }
    }

    /// Columns 0-4 and 24+ belong to the agent blocks, as for the desk.
    @Test func keepsClearOfTheAgentColumns() {
        for look in [Look.standard, Look(figure: .lidman), Look(figure: .clip)] {
            let plain = frames(0, look: look)
            for (i, f) in frames(3, look: look).enumerated() {
                for y in 8..<32 {
                    for x in [0, 1, 2, 3, 4, 27, 28, 29, 30, 31] where f.pixel(x, y) != plain[i].pixel(x, y) {
                        Issue.record("\(look.figure) frame \(i) draws at \(x),\(y)")
                    }
                }
            }
        }
    }
}
