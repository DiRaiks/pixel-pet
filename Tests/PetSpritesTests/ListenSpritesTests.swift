import Testing
import PetCore
@testable import PetSprites

@Suite struct ListenSpritesTests {
    func has(_ f: PixelCanvas, _ color: RGBA, x: Range<Int> = 0..<32, y: Range<Int> = 0..<32) -> Bool {
        y.contains { yy in x.contains { f.pixel($0, yy) == color } }
    }

    /// While listening the mic is out on the left, and waves come in only while there's sound.
    @Test func micOutWavesOnlyWithSound() {
        for look in [Look.standard, Look(figure: .lidman)] {
            for i in 0..<PetState.listening.frameCount {
                let f = SpriteFactory.frame(for: .listening, index: i, agentCubes: false, look: look)
                #expect(has(f, Palette.keyboardTop, x: 0..<12), "\(look.figure) mic \(i)")
                #expect(has(f, Palette.note, x: 0..<8) || has(f, Palette.tealLight, x: 0..<8), "\(look.figure) waves \(i)")
            }
            for i in 0..<PetState.listenQuiet.frameCount {
                let f = SpriteFactory.frame(for: .listenQuiet, index: i, agentCubes: false, look: look)
                #expect(has(f, Palette.keyboardTop, x: 0..<12))
                #expect(!has(f, Palette.note) && !has(f, Palette.tealLight))
            }
        }
    }

    /// The nod ends with the mic put away and the pet back on its spot.
    @Test func listenOutEndsLikeIdle() {
        let last = SpriteFactory.frame(for: .listenOut, index: PetState.listenOut.frameCount - 1, agentCubes: false)
        #expect(!has(last, Palette.keyboardTop))
        #expect(!has(last, Palette.keyboard, x: 0..<8))
    }
}
