import Testing
@testable import PetCore

@Suite struct TypingScriptTests {
    let beats = TypingScript.beats

    @Test func workingPlaysTheScript() {
        #expect(PetState.working.frameCount == beats.count)
        #expect(PetState.working.durations == beats.map { $0.ms / 1000 })
    }

    /// Long enough that the loop doesn't read as a loop, short enough to stay a handful of frames.
    @Test func loopLastsAboutTwelveSeconds() {
        #expect((10...14).contains(PetState.working.totalDuration))
        #expect(beats.count < 150)
    }

    /// Bursts differ in length and pace, and the pauses between them differ too.
    @Test func burstsAndPausesVary() {
        var bursts: [Int] = [], run = 0
        for (beat, _) in beats {
            if case .down = beat { run += 1 } else if case .up = beat {} else if run > 0 { bursts.append(run); run = 0 }
        }
        #expect(bursts == TypingScript.bursts)
        #expect(Set(bursts).count == bursts.count)
        let downs = beats.filter { if case .down = $0.beat { true } else { false } }.map(\.ms)
        #expect(Set(downs).count > 10)
        #expect(beats.contains { $0.beat == .blink })
        #expect(beats.contains { $0.beat == .hitch })
        #expect(beats.contains { $0.beat == .read })
    }

    /// Pins the generated loop: reordering the random draws would quietly change it.
    @Test func generatedLoopIsPinned() {
        #expect(beats.count == 113)
        #expect(abs(PetState.working.totalDuration - 12.284) < 0.000_1)
        #expect(beats.filter { $0.beat == .up && $0.ms == 170 }.count == 10)
        #expect(TypingScript.starts.first == 0)
        #expect(TypingScript.starts.last! + beats.last!.ms == 12_284)
    }

    @Test func keysStayOnTheKeyboard() {
        for (beat, ms) in beats {
            if case .down(let key) = beat { #expect((0..<TypingScript.keyCount).contains(key)) }
            #expect(ms >= 50 && ms <= 700)
        }
    }
}
