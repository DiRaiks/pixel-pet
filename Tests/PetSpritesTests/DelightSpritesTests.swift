import Testing
import PetCore
@testable import PetSprites

@Suite struct DelightSpritesTests {
    func has(_ f: PixelCanvas, _ color: RGBA, x: Range<Int> = 0..<32, y: Range<Int> = 0..<32) -> Bool {
        y.contains { yy in x.contains { f.pixel($0, yy) == color } }
    }

    /// The bubble shows only with a tool, only while typing, up and to the left of the head.
    @Test func toolBubbleWhileTyping() {
        let plain = SpriteFactory.frame(for: .working, index: 0, agentCubes: false)
        #expect(!has(plain, Palette.white, x: 0..<12, y: 0..<10))
        for tool in [WorkProps.toolRun, .toolSearch, .toolRead, .toolEdit] {
            for look in [Look.standard, Look(figure: .lidman)] {
                let f = SpriteFactory.frame(for: .working, index: 0, agentCubes: false, look: look, props: tool)
                #expect(has(f, Palette.white, x: 0..<12, y: 0..<10), "\(tool)")
                #expect(f != SpriteFactory.frame(for: .working, index: 0, agentCubes: false, look: look), "\(tool)")
            }
            #expect(SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, props: tool)
                    == SpriteFactory.frame(for: .idle, index: 0, agentCubes: false))
        }
    }

    @Test func holidayPropsByThePet() {
        for (prop, color) in [(WorkProps.pumpkin, Palette.pumpkin), (.fir, Palette.fir)] {
            for state in [PetState.idle, .working, .workSip, .yawn, .sneeze, .sleep] {
                #expect(has(SpriteFactory.frame(for: state, index: 0, agentCubes: false, props: prop), color), "\(state)")
            }
            for state in [PetState.peekHold, .dragged, .thrown] {
                #expect(!has(SpriteFactory.frame(for: state, index: 0, agentCubes: false, props: prop), color), "\(state)")
            }
        }
    }

    /// Columns 0-4 and 27-31 belong to the agent blocks: the new art stays out of them.
    @Test func newArtKeepsClearOfTheAgentColumns() {
        let blank = PixelCanvas()
        for look in [Look.standard, Look(figure: .lidman)] {
            for state in [PetState.wave, .launch, .purr, .sneeze] {
                for (i, f) in SpriteFactory.frames(for: state, agentCubes: false, look: look).enumerated() {
                    // Rows 0-7 above the blocks are free (the launch firework, the tool bubble).
                    for y in 8..<32 {
                        for x in [0, 1, 2, 3, 4, 27, 28, 29, 30, 31] where f.pixel(x, y) != blank.pixel(x, y) {
                            Issue.record("\(state) frame \(i) draws at \(x),\(y)")
                        }
                    }
                }
            }
            for prop in [WorkProps.pumpkin, .fir] {
                let f = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: look, props: prop)
                let bare = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false, look: look)
                for y in 8..<32 { for x in 0..<5 { #expect(f.pixel(x, y) == bare.pixel(x, y)) } }
            }
        }
    }

    /// The waving arm sticks out right of the body, above its middle.
    @Test func waveRaisesAnArm() {
        let frames = SpriteFactory.frames(for: .wave, agentCubes: false)
        let outline = Look.standard.skin.outline
        #expect(has(frames[2], outline, x: 21..<27, y: 8..<16))
        #expect(!has(frames[0], outline, x: 22..<27, y: 8..<16))
    }

    /// The rocket starts on the floor and is gone up top by the time the pet cheers.
    @Test func rocketTakesOff() {
        let frames = SpriteFactory.frames(for: .launch, agentCubes: false)
        func noseRow(_ f: PixelCanvas) -> Int? {
            (0..<32).first { y in (0..<10).contains { f.pixel($0, y) == Palette.rocketRed } }
        }
        #expect(noseRow(frames[0]) == 19)
        #expect(noseRow(frames[10])! < 10)
        #expect(noseRow(frames[18]) == nil)
    }

    @Test func pettingFloatsHearts() {
        let frames = SpriteFactory.frames(for: .purr, agentCubes: false)
        #expect(!has(frames[0], Palette.heart))
        #expect(has(frames[6], Palette.heart))
    }

    /// The cube sneezes mist, LM water.
    @Test func sneezeSpray() {
        let cube = SpriteFactory.frame(for: .sneeze, index: 6, agentCubes: false)
        let lm = SpriteFactory.frame(for: .sneeze, index: 6, agentCubes: false, look: Look(figure: .lidman))
        #expect(has(cube, Palette.menuBar, x: 24..<32))
        #expect(has(lm, Palette.water, x: 24..<32))
        #expect(!has(SpriteFactory.frame(for: .sneeze, index: 0, agentCubes: false), Palette.menuBar))
    }
}
