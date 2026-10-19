import Testing
@testable import PetCore

@Suite struct PetPlayerTests {
    @Test func startsOnFirstFrameOfBase() {
        let player = PetPlayer(base: .idle)
        #expect(player.state == .idle)
        #expect(player.frame == 0)
    }

    @Test func eachFrameKeepsItsOwnDuration() {
        var player = PetPlayer(base: .hop)
        let d = PetState.hop.durations
        #expect(player.advance(by: d[0] * 0.5) == false)
        #expect(abs(player.timeToNextFrame - d[0] * 0.5) < 1e-9)
        #expect(player.advance(by: d[0] * 0.5) == true)
        #expect(player.frame == 1)
        _ = player.advance(by: d[1] + d[2])
        #expect(player.frame == 3)
    }

    @Test func loopingStateWrapsAround() {
        var player = PetPlayer(base: .idle)
        _ = player.advance(by: PetState.idle.totalDuration)
        #expect(player.state == .idle)
        #expect(player.frame == 0)
    }

    @Test func oneShotReturnsToBaseWhenFinished() {
        var player = PetPlayer(base: .working)
        player.play(.hop)
        #expect(player.state == .hop)
        _ = player.advance(by: PetState.hop.totalDuration)
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
        _ = player.advance(by: PetState.celebrate.totalDuration)
        #expect(player.state == .sleep)
    }

    @Test func settingSameBaseDoesNotResetFrame() {
        var player = PetPlayer(base: .idle)
        _ = player.advance(by: PetState.idle.durations[0] + PetState.idle.durations[1])
        player.setBase(.idle)
        #expect(player.frame == 2)
    }

    @Test func playingLoopingStateMakesItTheBase() {
        var player = PetPlayer(base: .idle)
        player.play(.dragged)
        _ = player.advance(by: 10)
        #expect(player.state == .dragged)
    }

    @Test func everyStateHasFramesWithPositiveDurations() {
        for state in PetState.allCases {
            #expect(state.frameCount > 0, "\(state)")
            #expect(state.durations.allSatisfy { $0 > 0 && $0 < 2 }, "\(state)")
        }
    }

    @Test func keyPosesAreHeldLongerThanInBetweens() {
        // Hop: anticipation and landing are held; airborne frames are quick.
        let d = PetState.hop.durations
        #expect(d[1] > d[4])
        #expect(d[10] > d[4])
        // Idle blink is quicker than a normal idle frame.
        #expect(PetState.idle.durations[11] < PetState.idle.durations[0])
    }
}

@Suite struct PetPlayerEdgeTests {
    @Test func timeToNextFrameAfterSeveralFrames() {
        var player = PetPlayer(base: .hop)
        let d = PetState.hop.durations
        _ = player.advance(by: d[0] + d[1] + d[2] * 0.25)
        #expect(player.frame == 2)
        #expect(abs(player.timeToNextFrame - d[2] * 0.75) < 1e-9)
    }

    @Test func durationsAreCachedTables() {
        // Same values on every access, so the frame clock never allocates per tick.
        #expect(PetState.idle.durations == PetState.idle.durations)
        #expect(PetState.idle.frameCount == 24)
    }

    @Test func oneShotLeftoverTimeDoesNotSkipBaseFirstFrame() {
        var player = PetPlayer(base: .idle)
        player.play(.hop)
        _ = player.advance(by: PetState.hop.totalDuration + PetState.idle.durations[0] * 0.9)
        #expect(player.state == .idle)
        #expect(player.frame == 0)
    }

    @Test func newOneShotRestartsCurrentOne() {
        var player = PetPlayer(base: .idle)
        player.play(.hop)
        _ = player.advance(by: PetState.hop.durations[0] + PetState.hop.durations[1])
        player.play(.celebrate)
        #expect(player.state == .celebrate)
        #expect(player.frame == 0)
    }
}

@Suite struct SpriteHitTests {
    @Test func flipsViewYIntoSpriteRows() {
        #expect(SpriteHit.pixel(x: 0, y: 0, scale: 4, height: 32) == SpriteHit.Pixel(x: 0, y: 31))
        #expect(SpriteHit.pixel(x: 127.9, y: 127.9, scale: 4, height: 32) == SpriteHit.Pixel(x: 31, y: 0))
        #expect(SpriteHit.pixel(x: 40, y: 64, scale: 4, height: 32) == SpriteHit.Pixel(x: 10, y: 15))
    }
}
