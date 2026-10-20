import Testing
import PetCore
@testable import PetSprites

@Suite struct MacSpritesTests {
    func has(_ f: PixelCanvas, _ color: RGBA, x: Range<Int> = 0..<32, y: Range<Int> = 0..<32) -> Bool {
        y.contains { yy in x.contains { f.pixel($0, yy) == color } }
    }

    func looks(_ extras: LookExtras) -> [Look] {
        var cube = Look.standard, lm = Look(figure: .lidman)
        cube.extras = extras
        lm.extras = extras
        return [cube, lm]
    }

    /// Worn headphones follow the body in every upright pose: idle, typing, mid-hop.
    @Test func headphonesFollowTheBody() {
        for look in looks([.headphones]) {
            for (state, i) in [(PetState.idle, 0), (.working, 0), (.hop, 6)] {
                let f = SpriteFactory.frame(for: state, index: i, agentCubes: false, look: look)
                #expect(has(f, Palette.cushion), "\(look.figure) \(state)")
            }
            var bare = look
            bare.extras = []
            #expect(!has(SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: bare), Palette.cushion))
        }
    }

    @Test func partyHatOnBothFigures() {
        for look in looks([.partyHat]) {
            let f = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: look)
            #expect(has(f, Palette.hatStripe), "\(look.figure)")
            #expect(has(f, Palette.sun, y: 0..<12), "\(look.figure): pompom on the canvas")
        }
        // Not over a hat the cube already wears.
        var capped = Look(skin: .lavender, accessory: .cap)
        capped.extras = [.partyHat]
        #expect(!has(SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: capped), Palette.hatStripe))
    }

    /// Headphones land on the head: the last frame of putting them on wears them like the worn look.
    @Test func headphonesOnEndsWorn() {
        for look in looks([.headphones]) {
            let frames = SpriteFactory.frames(for: .headphonesOn, agentCubes: false, look: look)
            #expect(!has(frames[0], Palette.cushion, y: 14..<32), "\(look.figure): starts above the head")
            #expect(has(frames[6], Palette.cushion, y: 14..<32), "\(look.figure): on the head")
        }
    }

    @Test func eachMomentShowsItsSign() {
        let cube = Look.standard
        #expect(has(SpriteFactory.frame(for: .onAir, index: 0, agentCubes: false, look: cube), Palette.rec))
        #expect(has(SpriteFactory.frame(for: .overheated, index: 0, agentCubes: false, look: cube), Palette.rec))
        #expect(has(SpriteFactory.frame(for: .lowPower, index: 0, agentCubes: false, look: cube), Palette.sun))
        #expect(has(SpriteFactory.frame(for: .offline, index: 0, agentCubes: false, look: cube), Palette.rec))
        #expect(has(SpriteFactory.frame(for: .music, index: 0, agentCubes: false, look: cube), Palette.note))
        #expect(has(SpriteFactory.frame(for: .batteryFull, index: 6, agentCubes: false, look: cube), Palette.batteryGreen))
        #expect(has(SpriteFactory.frame(for: .screenshot, index: 6, agentCubes: false, look: cube), RGBA(0xFFD56B)))
        #expect(has(SpriteFactory.frame(for: .darkMode, index: 6, agentCubes: false, look: cube), Palette.moon))
        #expect(has(SpriteFactory.frame(for: .lightMode, index: 7, agentCubes: false, look: cube), Palette.lens))
    }

    /// Columns 0-4 and 27-31 below row 8 belong to the agent blocks (row 8 itself only to the 5+ overflow mark,
    /// which the bubbles share, like the tool bubble does).
    @Test func keepsClearOfTheAgentColumns() {
        let states: [PetState] = [.headphonesOn, .headphonesOff, .music, .onAir, .overheated, .lowPower, .offline,
                                  .batteryFull, .screenshot, .darkMode, .lightMode]
        for look in looks([.headphones, .partyHat]) {
            for state in states {
                for (i, f) in SpriteFactory.frames(for: state, agentCubes: false, look: look).enumerated()
                where !(state == .screenshot && i == 2) {
                    for y in ([.onAir, .offline].contains(state) ? 9 : 8)..<32 {
                        for x in [0, 1, 2, 3, 4, 27, 28, 29, 30, 31] where f.pixel(x, y) != nil {
                            Issue.record("\(look.figure) \(state) frame \(i) draws at \(x),\(y)")
                        }
                    }
                }
            }
        }
    }
}
