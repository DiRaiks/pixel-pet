import Foundation
import Testing
@testable import PetCore

@Suite struct ListenTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// The dots come after a moment of quiet and go as soon as there's sound again.
    @Test func quietAfterAMomentWithoutSound() {
        var clock = ListenClock(started: t0, handsFree: false)
        let quiet = [(-60, 1.0), (-60, 1.6), (-20, 2.0), (-60, 3.0), (-60, 3.6)].map { level, t in
            clock.update(level: Float(level), at: at(t))
        }
        #expect(quiet == [false, true, false, false, true])
    }

    /// Held down, only letting go ends it (or the two-minute cap); a pause doesn't.
    @Test func heldDownIgnoresPauses() {
        var clock = ListenClock(started: t0, handsFree: false)
        clock.update(level: -20, at: at(1))
        #expect(!clock.shouldStop(at: at(30)))
        #expect(clock.shouldStop(at: at(ListenClock.longest)))
    }

    /// Hands-free, a pause after speech ends it; with nothing said, it gives up a bit later.
    @Test func handsFreeStopsOnAPauseOrSilence() {
        var talked = ListenClock(started: t0, handsFree: true)
        talked.update(level: -20, at: at(2))
        #expect(!talked.shouldStop(at: at(5)))
        #expect(talked.shouldStop(at: at(6)))
        let silent = ListenClock(started: t0, handsFree: true)
        #expect(!silent.shouldStop(at: at(9)))
        #expect(silent.shouldStop(at: at(ListenClock.nothingToStop)))
    }

    /// Settled pieces are kept and joined; the guess in progress is replaced by the next one.
    @Test func transcriptJoinsSettledPiecesAndReplacesTheGuess() {
        var t = Transcript()
        t.apply("Привет", final: false)
        t.apply("Привет кубик", final: false)
        #expect(t.text == "Привет кубик")
        t.apply("Привет кубик.", final: true)
        t.apply(" Как", final: false)
        #expect(t.text == "Привет кубик. Как")
        t.apply("Как дела?", final: true)
        #expect(t.text == "Привет кубик. Как дела?")
        #expect(t.pending.isEmpty)
    }

    /// Listening is a loop the controller swaps between; the perk-up and the nod are one-shots, and both
    /// move, so reduce motion skips them.
    @Test func listenStatesLoopAndMotion() {
        #expect(PetState.listening.loops && PetState.listenQuiet.loops)
        #expect(!PetState.listenIn.loops && !PetState.listenOut.loops)
        #expect(!MotionPolicy.allowsOneShot(.listenIn) && !MotionPolicy.allowsOneShot(.listenOut))
        #expect(MotionPolicy.stillFrame(for: .listening) == 0)
    }

    /// Speech defaults to "my language" and remembers a choice of its own.
    @Test func speechLanguageFollowsMyLanguageUnlessSet() throws {
        var config = PetConfig()
        config.nativeLanguage = "ru"
        #expect(config.spokenLanguage == "ru")
        config.speechLanguage = "en"
        #expect(config.spokenLanguage == "en")
        let decoded = try JSONDecoder().decode(PetConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.speechLanguage == "en")
        #expect(try JSONDecoder().decode(PetConfig.self, from: Data("{}".utf8)).speechLanguage == "")
    }
}
