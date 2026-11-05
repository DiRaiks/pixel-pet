import Testing
import PetCore
@testable import PetSprites

/// Loops that can run for hours stay calm: intros play once, motion is slow and sparse.
@Suite struct CalmLoopTests {
    private func frames(_ state: PetState) -> [PixelCanvas] { SpriteFactory.frames(for: state, agentCubes: false) }

    /// How many times the frames change between neighbours over one loop (seam included).
    private func changes<T: Equatable>(_ values: [T]) -> Int {
        zip(values, values.dropFirst() + [values[0]]).filter { $0 != $1 }.count
    }

    private func topRow(_ f: PixelCanvas, _ color: RGBA) -> Int? {
        (0..<f.height).first { y in (0..<f.width).contains { f.pixel($0, y) == color } }
    }

    /// The error's flash and shake, and the low limit's shake, play once on entry; the loop goes on after.
    @Test func introsPlayOnce() {
        for state in [PetState.error, .lowLimit] {
            var player = PetPlayer(base: state)
            player.advance(by: state.totalDuration)
            #expect(player.frame == state.loopStart, "\(state)")
            for _ in 0..<40 {
                player.advance(by: 0.05)
                #expect(player.frame >= state.loopStart, "\(state)")
            }
        }
        #expect(PetState.idle.loopStart == 0)
    }

    /// While typing, the body dips on a few accents per burst, not on every key.
    @Test func typingDipsOnlyOnAccents() {
        let downs = TypingScript.beats.indices.filter { if case .down = TypingScript.beats[$0].beat { true } else { false } }
        let accents = downs.filter(TypingScript.isAccent)
        #expect(!accents.isEmpty)
        #expect(accents.count * 3 < downs.count * 2)
        #expect(accents.count <= TypingScript.bursts.count * 2)
    }

    /// Idle breathes twice a loop, and the highlight stays off the eyes.
    @Test func idleBreathesSlowly() {
        let idle = frames(.idle)
        let highlight = Skin.lavender.highlight
        #expect(changes(idle.map { topRow($0, highlight) }) <= 4)
        for f in idle {
            for y in 0..<f.height { for x in 0..<f.width where f.pixel(x, y) == highlight {
                #expect(f.pixel(x + 1, y) != Skin.lavender.eye && f.pixel(x, y + 1) != Skin.lavender.eye)
            } }
        }
    }

    /// Sleep breathes at 1.2 s a phase.
    @Test func sleepBreathesSlowly() {
        let d = PetState.sleep.durations
        #expect(d[0] + d[1] >= 1.2)
    }

    /// The offline slash stays; the tired battery blinks once a loop; the meeting clock ticks, not spins.
    @Test func statusIconsHoldStill() {
        #expect(frames(.offline).allSatisfy { $0.pixels.contains(Palette.rec) })
        #expect(changes(frames(.tired).map { $0.pixels.filter { $0 == Palette.batteryRed }.count }) <= 2)
        #expect(changes(frames(.meetingSoon).map { $0.pixels.filter { $0 == Palette.accessoryDark }.count }) <= 8)
    }

    /// Music bobs without swaying, and overheating pants at half the old rate.
    @Test func ongoingMovesAreSparse() {
        let outline = Skin.lavender.outline
        let lefts = frames(.music).map { f in (0..<f.width).first { x in (0..<f.height).contains { f.pixel(x, $0) == outline } } }
        #expect(Set(lefts).count == 1)
        let widths = frames(.overheated).map { f in (0..<f.width).filter { x in (0..<f.height).contains { f.pixel(x, $0) == outline } }.count }
        #expect(changes(widths) <= 4)
    }
}
