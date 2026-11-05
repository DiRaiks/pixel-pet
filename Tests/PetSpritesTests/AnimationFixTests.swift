import Testing
import PetCore
@testable import PetSprites

/// Regressions from the animation review: props drawn off the canvas or over the body, and turns that
/// read wrong.
@Suite struct AnimationFixTests {
    private func frame(_ state: PetState, _ i: Int, _ look: Look = .standard) -> PixelCanvas {
        SpriteFactory.frame(for: state, index: i, agentCubes: false, look: look)
    }

    private func count(_ f: PixelCanvas, _ color: RGBA) -> Int { f.pixels.filter { $0 == color }.count }

    /// The "quiet" dots come one by one, all on the canvas (they used to land past its right edge).
    @Test func quietDotsAreOnTheCanvas() {
        let none = count(frame(.listenQuiet, 0), Palette.keyboard)
        #expect(count(frame(.listenQuiet, 3), Palette.keyboard) == none + 3)
        for i in 0..<PetState.listenQuiet.frameCount {
            let f = frame(.listenQuiet, i)
            #expect((0..<f.height).allSatisfy { f.pixel(f.width - 1, $0) == nil })
        }
    }

    /// The screenshot flash lights the pet, not the whole (clear) canvas.
    @Test func screenshotFlashKeepsTheCanvasClear() {
        let f = frame(.screenshot, 2)
        #expect(f.pixel(0, 0) == nil && f.pixel(31, 31) == nil && f.pixel(31, 0) == nil)
    }

    /// Celebration sparkles never touch the body's outline (they used to land on the face mid-air).
    @Test func celebrationSparklesStayOffTheBody() {
        let outline = Skin.lavender.outline
        for i in 5...14 {
            let f = frame(.celebrate, i)
            for y in 0..<f.height { for x in 0..<f.width where f.pixel(x, y) == Palette.amber || f.pixel(x, y) == Palette.teal {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { #expect(f.pixel(x + dx, y + dy) != outline) }
            } }
        }
    }

    /// Looking aside moves the eyes, not the cheeks: no blush pixel ends up on the edge of the silhouette.
    @Test func blushStaysInsideWhenLookingAside() {
        let blush = Skin.lavender.blush
        for state in [PetState.glanceLeft, .glanceRight, .question, .talk, .spawnDesk] {
            for i in 0..<state.frameCount {
                let f = frame(state, i)
                for y in 0..<f.height { for x in 0..<f.width where f.pixel(x, y) == blush {
                    #expect(f.pixel(x - 1, y) != nil && f.pixel(x + 1, y) != nil, "\(state) \(i) at \(x),\(y)")
                } }
            }
        }
    }

    /// The somersault's turning frames show a tilt that keeps growing (60/150/240/320° all showed one tilt,
    /// since a faceless square repeats every 90°), and the turn still adds up to a full one.
    @Test func somersaultVisiblyTurnsForward() {
        let angles = (4...7).map { SpriteFactory.flipKeys[$0].3 }
        let visible = angles.map { $0.truncatingRemainder(dividingBy: 90) }
        #expect(zip(visible, visible.dropFirst()).allSatisfy { $0 < $1 })
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 < $1 })
        #expect(SpriteFactory.flipKeys[8].3 == 360)
    }

    /// The thrown spin only ever turns forward (a quarter or not at all per frame) and lands upright;
    /// it used to roll a quarter back on the second-to-last frame.
    @Test func thrownSpinDoesNotReverse() {
        let turns = SpriteFactory.thrownKeys.map(\.turns)
        #expect(zip(turns, turns.dropFirst()).allSatisfy { [0, 1].contains(($1 - $0 + 4) % 4) })
        #expect(turns.last == 0)
    }

    /// The thermometer stays near the top through the loop seam instead of dropping and rising again.
    @Test func thermometerHoldsAcrossTheLoop() {
        let n = PetState.overheated.frameCount
        let levels = (0..<n).map { count(frame(.overheated, $0), Palette.rec) }
        #expect(abs(levels[n - 1] - levels[0]) <= 1)
        #expect(levels.max()! - levels.min()! <= 1)
    }
}
