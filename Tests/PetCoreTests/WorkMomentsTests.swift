import Foundation
import Testing
@testable import PetCore

@Suite struct WorkMomentsTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func propsPileUpAsWorkGoesOn() {
        #expect(WorkStage.stage(worked: nil) == .fresh)
        #expect(WorkStage.stage(worked: 9 * 60) == .fresh)
        #expect(WorkStage.stage(worked: 10 * 60) == .mug)
        #expect(WorkStage.stage(worked: 31 * 60) == .headband)
    }

    /// The monitor wakes up exactly when the next prop should appear, and not at all after the last one.
    @Test func nextStageChangeIsScheduled() {
        #expect(WorkStage.nextChange(worked: 60, now: t0) == t0.addingTimeInterval(WorkStage.mugAfter - 60))
        #expect(WorkStage.nextChange(worked: 15 * 60, now: t0) == t0.addingTimeInterval(WorkStage.headbandAfter - 15 * 60))
        #expect(WorkStage.nextChange(worked: 40 * 60, now: t0) == nil)
        #expect(WorkStage.nextChange(worked: nil, now: t0) == nil)
    }

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    /// Many short turns in a row add up: the pauses between them (reading, typing the next message,
    /// answering a question) don't count, but don't wipe the desk either.
    @Test func workSessionAddsUpTurnsAcrossShortPauses() {
        var w = WorkSession()
        w.update(working: true, now: minutes(0))
        w.update(working: false, now: minutes(6))
        #expect(w.worked(now: minutes(8)) == 6 * 60)
        w.update(working: true, now: minutes(9))
        #expect(w.worked(now: minutes(14)) == 11 * 60)
        #expect(WorkStage.stage(worked: w.worked(now: minutes(14))) == .mug)
    }

    @Test func aLongBreakClearsTheDesk() {
        var w = WorkSession()
        w.update(working: true, now: minutes(0))
        w.update(working: false, now: minutes(20))
        #expect(w.worked(now: minutes(20) + WorkSession.grace + 1) == 0)
        w.update(working: true, now: minutes(20) + WorkSession.grace + 60)
        #expect(w.worked(now: minutes(20) + WorkSession.grace + 120) == 60)
    }

    /// Updates arrive with every agent event; repeating the same state changes nothing.
    @Test func repeatedUpdatesAreHarmless() {
        var w = WorkSession()
        for m in 0..<5 { w.update(working: true, now: minutes(Double(m))) }
        #expect(w.worked(now: minutes(5)) == 5 * 60)
        for m in 5..<8 { w.update(working: false, now: minutes(Double(m))) }
        #expect(w.worked(now: minutes(8)) == 5 * 60)
    }

    /// The next prop is only scheduled while the work goes on.
    @Test func nextPropOnlyWhileWorking() {
        var w = WorkSession()
        w.update(working: true, now: minutes(0))
        #expect(w.nextChange(now: minutes(4)) == minutes(10))
        w.update(working: false, now: minutes(5))
        #expect(w.nextChange(now: minutes(6)) == nil)
    }

    @Test func momentsDoNotRepeatBackToBack() {
        for last in WorkMoments.pool {
            for roll in 0..<20 {
                let next = WorkMoments.pick(after: last, roll: roll)
                #expect(next != last)
                #expect(WorkMoments.pool.contains(next))
            }
        }
        // Every moment comes up.
        #expect(Set((0..<20).map { WorkMoments.pick(after: nil, roll: $0) }) == Set(WorkMoments.pool))
    }

    @Test func momentDelayStaysInRange() {
        for _ in 0..<50 { #expect(WorkMoments.range.contains(WorkMoments.delay())) }
    }

    /// Worth a look: an agent finishing, failing, starting to wait or to work, or a new one joining others.
    @Test func meaningfulChangesAreNoticed() {
        let working = AgentCube(status: .working, subagents: 0), idle = AgentCube(status: .idle, subagents: 0)
        let done = AgentCube(status: .done, subagents: 0), failed = AgentCube(status: .failed, subagents: 0)
        let waiting = AgentCube(status: .waiting, subagents: 0)
        #expect(WorkMoments.noticeable(old: [working], new: [done]))
        #expect(WorkMoments.noticeable(old: [working], new: [failed]))
        #expect(WorkMoments.noticeable(old: [working], new: [waiting]))
        #expect(WorkMoments.noticeable(old: [idle], new: [working]))
        #expect(WorkMoments.noticeable(old: [working], new: [working, working]))
    }

    /// Not worth a look: subagents, the green flash fading, a session dropping off (and the blocks after it
    /// moving down a slot), or the very first blocks showing up at launch.
    @Test func noiseIsIgnored() {
        let working = AgentCube(status: .working, subagents: 0), idle = AgentCube(status: .idle, subagents: 0)
        let done = AgentCube(status: .done, subagents: 0)
        #expect(!WorkMoments.noticeable(old: [working], new: [AgentCube(status: .working, subagents: 2)]))
        #expect(!WorkMoments.noticeable(old: [done], new: [idle]))
        #expect(!WorkMoments.noticeable(old: [idle, working, idle], new: [working, idle]))
        #expect(!WorkMoments.noticeable(old: [], new: [working, working]))
        #expect(!WorkMoments.noticeable(old: [], new: []))
    }

    @Test func deskStatesAreTheKeyboardFamily() {
        let desk: Set<PetState> = [.working, .workSip, .workStretch, .workThink, .workRush, .glanceLeft, .glanceRight,
                                   .spawnDesk, .recallDesk]
        #expect(Set(PetState.allCases.filter(\.isAtDesk)) == desk)
        for state in desk where state != .working {
            #expect(!state.loops)
            #expect(!MotionPolicy.allowsOneShot(state))
        }
    }
}
