import Foundation
import Testing
@testable import PetCore

@Suite struct MotionPolicyTests {
    @Test func movementHeavyStatesHoldOneTellingFrame() {
        #expect(MotionPolicy.stillFrame(for: .alert) == 0)
        #expect(MotionPolicy.stillFrame(for: .error) == 2)
        #expect(MotionPolicy.stillFrame(for: .dragged) == 0)
        #expect(MotionPolicy.stillFrame(for: .lowLimit) == 8)
    }

    @Test func gentleStatesKeepAnimating() {
        for state in [PetState.idle, .working, .sleep, .talk, .burrowed, .peekHold] {
            #expect(MotionPolicy.stillFrame(for: state) == nil, "\(state)")
        }
    }

    @Test func stillFramesExist() {
        for state in PetState.allCases {
            if let frame = MotionPolicy.stillFrame(for: state) { #expect(frame < state.frameCount, "\(state)") }
        }
    }

    @Test func jumpsAndDivesAreSkipped() {
        for state in [PetState.hop, .celebrate, .drop, .dive, .peek] {
            #expect(!MotionPolicy.allowsOneShot(state), "\(state)")
        }
    }

    @Test func onboardingFlagDefaultsOffAndRoundTrips() throws {
        let old = try JSONDecoder().decode(PetConfig.self, from: Data(#"{"scale":4}"#.utf8))
        #expect(old.onboarded == false)
        var c = PetConfig()
        c.onboarded = true
        #expect(try JSONDecoder().decode(PetConfig.self, from: JSONEncoder().encode(c)).onboarded)
    }
}

@Suite struct MotionCueTests {
    @Test func skippedEventsStillLeaveAQuietSign() {
        // Finished: a held happy face standing still. Event at home: the eyes out of the hole, held.
        #expect(MotionPolicy.cue(for: .celebrate) == MotionPolicy.Cue(state: .celebrate, frame: 12))
        #expect(MotionPolicy.cue(for: .peek) == MotionPolicy.Cue(state: .peekHold, frame: 0))
    }

    @Test func cuesAreStillFramesThatExist() {
        for state in PetState.allCases {
            guard let cue = MotionPolicy.cue(for: state) else { continue }
            #expect(cue.frame < cue.state.frameCount)
        }
    }

    @Test func clickAndLandingNeedNoCue() {
        for state in [PetState.hop, .drop, .dive] { #expect(MotionPolicy.cue(for: state) == nil) }
    }
}
