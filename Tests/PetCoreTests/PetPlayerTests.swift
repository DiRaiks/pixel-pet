import Testing
@testable import PetCore

@Suite struct PetPlayerTests {
    @Test func startsOnFirstFrameOfBase() {
        let player = PetPlayer(base: .idle)
        #expect(player.state == .idle)
        #expect(player.frame == 0)
    }

    @Test func advancesFramesAtStateFps() {
        var player = PetPlayer(base: .idle)
        let step = 1 / PetState.idle.fps
        #expect(player.advance(by: step * 0.5) == false)
        #expect(player.advance(by: step * 0.5) == true)
        #expect(player.frame == 1)
        _ = player.advance(by: step * 3)
        #expect(player.frame == 4)
    }

    @Test func loopingStateWrapsAround() {
        var player = PetPlayer(base: .idle)
        _ = player.advance(by: Double(PetState.idle.frameCount) / PetState.idle.fps)
        #expect(player.state == .idle)
        #expect(player.frame == 0)
    }

    @Test func oneShotReturnsToBaseWhenFinished() {
        var player = PetPlayer(base: .working)
        player.play(.hop)
        #expect(player.state == .hop)
        #expect(player.frame == 0)
        _ = player.advance(by: Double(PetState.hop.frameCount) / PetState.hop.fps)
        #expect(player.state == .working)
        #expect(player.frame == 0)
    }

    @Test func oneShotIgnoresLargeDeltaOverflow() {
        var player = PetPlayer(base: .idle)
        player.play(.hop)
        _ = player.advance(by: 100)
        #expect(player.state == .idle)
        #expect(player.frame < PetState.idle.frameCount)
    }

    @Test func settingBaseDuringOneShotKeepsOneShot() {
        var player = PetPlayer(base: .idle)
        player.play(.celebrate)
        player.setBase(.sleep)
        #expect(player.state == .celebrate)
        _ = player.advance(by: Double(PetState.celebrate.frameCount) / PetState.celebrate.fps)
        #expect(player.state == .sleep)
    }

    @Test func settingSameBaseDoesNotResetFrame() {
        var player = PetPlayer(base: .idle)
        _ = player.advance(by: 2 / PetState.idle.fps)
        player.setBase(.idle)
        #expect(player.frame == 2)
    }

    @Test func playingLoopingStateMakesItTheBase() {
        var player = PetPlayer(base: .idle)
        player.play(.dragged)
        #expect(player.state == .dragged)
        _ = player.advance(by: 10)
        #expect(player.state == .dragged)
    }

    @Test func everyStateHasPositiveTiming() {
        for state in PetState.allCases {
            #expect(state.frameCount > 0, "\(state)")
            #expect(state.fps > 0, "\(state)")
        }
    }
}

@Suite struct PetPlayerEdgeTests {
    @Test func oneShotLeftoverTimeDoesNotSkipBaseFirstFrame() {
        var player = PetPlayer(base: .idle)
        player.play(.hop)
        _ = player.advance(by: Double(PetState.hop.frameCount) / PetState.hop.fps + 0.9 / PetState.hop.fps)
        #expect(player.state == .idle)
        #expect(player.frame == 0)
    }

    @Test func newOneShotRestartsCurrentOne() {
        var player = PetPlayer(base: .idle)
        player.play(.hop)
        _ = player.advance(by: 3 / PetState.hop.fps)
        player.play(.celebrate)
        #expect(player.state == .celebrate)
        #expect(player.frame == 0)
    }
}

@Suite struct SpriteHitTests {
    @Test func flipsViewYIntoSpriteRows() {
        // Bottom-left view origin, top-left sprite origin, scale 4.
        #expect(SpriteHit.pixel(x: 0, y: 0, scale: 4, height: 32) == SpriteHit.Pixel(x: 0, y: 31))
        #expect(SpriteHit.pixel(x: 127.9, y: 127.9, scale: 4, height: 32) == SpriteHit.Pixel(x: 31, y: 0))
        #expect(SpriteHit.pixel(x: 40, y: 64, scale: 4, height: 32) == SpriteHit.Pixel(x: 10, y: 15))
    }
}
