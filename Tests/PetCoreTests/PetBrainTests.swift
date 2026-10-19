import Foundation
import Testing
@testable import PetCore

@Suite struct PetBrainTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func session(_ id: String, _ status: AgentSession.Status, failedAgo: Double? = nil, finishedAgo: Double? = nil,
                 subagents: Set<String> = []) -> AgentSession {
        var s = AgentSession(id: id, firstSeenAt: now, lastEventAt: now)
        s.status = status
        s.failedAt = failedAgo.map { now.addingTimeInterval(-$0) }
        s.finishedAt = finishedAgo.map { now.addingTimeInterval(-$0) }
        s.subagents = subagents
        return s
    }

    @Test func idleWithoutSessions() {
        #expect(PetBrain.baseState(for: [], now: now) == .idle)
    }

    @Test func priorityErrorThenAlertThenWorking() {
        let working = session("w", .working), waiting = session("q", .waiting), failed = session("f", .failed, failedAgo: 1)
        #expect(PetBrain.baseState(for: [working], now: now) == .working)
        #expect(PetBrain.baseState(for: [working, waiting], now: now) == .alert)
        #expect(PetBrain.baseState(for: [working, waiting, failed], now: now) == .error)
    }

    @Test func errorFadesAfterWindow() {
        let failed = session("f", .failed, failedAgo: PetBrain.errorWindow + 0.1)
        #expect(PetBrain.baseState(for: [failed], now: now) == .idle)
    }

    @Test func cubesReflectStatusesAndDoneFlash() {
        let cubes = PetBrain.cubes(for: [
            session("a", .working, subagents: ["x", "y"]),
            session("b", .idle, finishedAgo: 0.5),
            session("c", .idle, finishedAgo: 10),
            session("d", .failed, failedAgo: 100),
        ], now: now)
        #expect(cubes == [AgentCube(status: .working, subagents: 2), AgentCube(status: .done, subagents: 0),
                          AgentCube(status: .idle, subagents: 0), AgentCube(status: .failed, subagents: 0)])
    }

    @Test func nextChangeIsEarliestExpiry() {
        let s = [session("f", .failed, failedAgo: 1), session("d", .idle, finishedAgo: 0.5)]
        #expect(PetBrain.nextChange(for: s, now: now) == now.addingTimeInterval(PetBrain.doneFlash - 0.5))
        #expect(PetBrain.nextChange(for: [session("w", .working)], now: now) == nil)
    }

    @Test func activeCountIgnoresIdleSessions() {
        #expect(PetBrain.activeCount([session("a", .working), session("b", .waiting), session("c", .idle)]) == 2)
    }
}
