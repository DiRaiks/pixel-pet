import Testing
import PetCore
@testable import PetSprites

@Suite struct AgentStackTests {
    @Test func emptyStackDrawsNothing() {
        #expect(AgentStack.canvas(for: [], tick: 0).opaquePixelCount == 0)
    }

    @Test func cubesStackUpwardFromTheGround() {
        let c = AgentStack.canvas(for: [AgentCube(status: .idle, subagents: 0), AgentCube(status: .idle, subagents: 0)], tick: 0)
        #expect(c.pixel(AgentStack.x, AgentStack.bottomY) == Palette.agentIdle)
        #expect(c.pixel(AgentStack.x, AgentStack.bottomY - AgentStack.step) == Palette.agentIdle)
        #expect(c.pixel(AgentStack.x, AgentStack.bottomY - 2 * AgentStack.step) == nil)
    }

    @Test func statusColors() {
        let c = AgentStack.canvas(for: [AgentCube(status: .failed, subagents: 0), AgentCube(status: .done, subagents: 0)], tick: 1)
        #expect(c.pixels.contains(Palette.errorFill))
        #expect(c.pixels.contains(Palette.agentDone))
    }

    @Test func waitingCubeBounces() {
        let cube = [AgentCube(status: .waiting, subagents: 0)]
        let ys = (0..<12).map { tick in
            (0..<32).first { y in AgentStack.canvas(for: cube, tick: tick).pixel(AgentStack.x + 2, y) != nil }
        }
        #expect(Set(ys).count == 2)
    }

    @Test func overflowShowsEllipsisInsteadOfFifthCube() {
        let many = Array(repeating: AgentCube(status: .working, subagents: 0), count: 7)
        let c = AgentStack.canvas(for: many, tick: 0)
        let topY = AgentStack.bottomY - 4 * AgentStack.step + 1
        #expect(c.pixel(AgentStack.x, topY) == Palette.shade)
        #expect(c.pixel(AgentStack.x + 1, topY) == nil)
    }

    @Test func subagentsShowAsDot() {
        let c = AgentStack.canvas(for: [AgentCube(status: .working, subagents: 1)], tick: 0)
        #expect(c.pixel(AgentStack.x + 3, AgentStack.bottomY) == Palette.tealLight)
    }

    @Test func bareFramesHaveNoBuiltInCubes() {
        for state in [PetState.working, .alert, .error] {
            let bare = SpriteFactory.frames(for: state, agentCubes: false)
            #expect(bare.allSatisfy { frame in (24..<32).allSatisfy { x in (0..<32).allSatisfy { frame.pixel(x, $0) == nil || frame.pixel(x, $0) == Palette.shadow } } },
                    "\(state)")
        }
    }

    /// Codex agents stack on the left, mirroring Claude's column on the right.
    @Test func codexColumnMirrorsOnTheLeft() {
        let c = AgentStack.canvas(for: [], left: [AgentCube(status: .idle, subagents: 0)], tick: 0)
        #expect(c.pixel(AgentStack.leftX, AgentStack.bottomY) == Palette.agentIdle)
        #expect(c.pixel(AgentStack.x, AgentStack.bottomY) == nil)
        let both = AgentStack.canvas(for: [AgentCube(status: .failed, subagents: 0)],
                                     left: [AgentCube(status: .idle, subagents: 0), AgentCube(status: .idle, subagents: 0)], tick: 0)
        #expect(both.pixel(AgentStack.x, AgentStack.bottomY) == Palette.errorFill)
        #expect(both.pixel(AgentStack.leftX, AgentStack.bottomY - AgentStack.step) == Palette.agentIdle)
        #expect(both.pixel(AgentStack.x, AgentStack.bottomY - AgentStack.step) == nil)
    }

    @Test func leftSubagentDotSitsOnTheOuterCorner() {
        let c = AgentStack.canvas(for: [], left: [AgentCube(status: .idle, subagents: 2)], tick: 0)
        #expect(c.pixel(AgentStack.leftX - 1, AgentStack.bottomY) == Palette.tealLight)
        #expect(c.pixel(AgentStack.leftX, AgentStack.bottomY) == Palette.agentIdle)
    }

    @Test func leftOverflowShowsEllipsis() {
        let many = Array(repeating: AgentCube(status: .idle, subagents: 0), count: 7)
        let c = AgentStack.canvas(for: [], left: many, tick: 0)
        let topY = AgentStack.bottomY - (AgentStack.maxVisible - 1) * AgentStack.step + 1
        #expect(c.pixel(AgentStack.leftX, topY) == Palette.shade)
    }

    /// The left column stays clear of the body in the poses the pet holds while agents run.
    @Test func restingPosesLeaveTheLeftColumnFree() {
        for state in [PetState.idle, .working, .alert, .lowLimit, .talk, .sleep, .dragged] {
            for (i, frame) in SpriteFactory.frames(for: state, agentCubes: false).enumerated() {
                let used = (0..<32).contains { y in (0...(AgentStack.leftX + 2)).contains { frame.pixel($0, y) != nil && y < 30 } }
                #expect(!used, "\(state) frame \(i) reaches into the left column")
            }
        }
    }
}
