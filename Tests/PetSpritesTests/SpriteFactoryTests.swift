import Testing
import PetCore
@testable import PetSprites

@Suite struct SpriteFactoryTests {
    @Test(arguments: PetState.allCases)
    func producesOneCanvasPerFrame(state: PetState) {
        let frames = SpriteFactory.frames(for: state)
        #expect(frames.count == state.frameCount)
        for (i, canvas) in frames.enumerated() {
            #expect(canvas.width == 32 && canvas.height == 32)
            #expect(canvas.opaquePixelCount > 100, "\(state) frame \(i) looks empty")
        }
    }

    @Test func framesAreDeterministic() {
        #expect(SpriteFactory.frames(for: .celebrate) == SpriteFactory.frames(for: .celebrate))
    }

    @Test func backgroundIsTransparent() {
        let idle = SpriteFactory.frames(for: .idle)[0]
        #expect(idle.pixel(0, 0) == nil)
        #expect(idle.pixel(31, 0) == nil)
    }

    @Test func idleBodyMatchesPrototypeGeometry() {
        let idle = SpriteFactory.frames(for: .idle)[0]
        // Body 16x14 at x0=8, y0=12; rounded corners are cut.
        #expect(idle.pixel(8, 12) == nil)
        #expect(idle.pixel(9, 12) == Palette.outline)
        #expect(idle.pixel(10, 15) == Palette.highlight)
        #expect(idle.pixel(11, 20) == Palette.fill)
        // Left eye with a glint in its top-left pixel.
        #expect(idle.pixel(12, 16) == Palette.glint)
        #expect(idle.pixel(13, 17) == Palette.eye)
    }

    @Test func blinkClosesEyes() {
        let blink = SpriteFactory.frames(for: .idle)[11]
        #expect(blink.pixel(12, 16) == Palette.fill)
        #expect(blink.pixel(12, 18) == Palette.eye)
    }

    @Test func errorFlashesRed() {
        let frame = SpriteFactory.frames(for: .error)[2]
        #expect(frame.pixels.contains(Palette.errorFill))
    }

    @Test func peekStartsHiddenInsideTheNotch() {
        let hidden = SpriteFactory.frames(for: .peek)[0]
        #expect(hidden.pixel(6, 2) == Palette.notch)
        #expect(!hidden.pixels.contains(Palette.fill))
        #expect(hidden.pixels.contains(Palette.glow))
    }

    @Test func lowLimitShowsDrainedTop() {
        let frame = SpriteFactory.frames(for: .lowLimit)[0]
        #expect(frame.pixels.contains(Palette.empty))
    }

    @Test func makesCGImageOfCanvasSize() throws {
        let image = try #require(SpriteFactory.frames(for: .idle)[0].makeImage())
        #expect(image.width == 32 && image.height == 32)
    }
}

@Suite struct MenuIconTests {
    @Test func isSilhouetteWithEyeHoles() {
        let icon = SpriteFactory.menuIcon()
        #expect(icon.width == 18 && icon.height == 18)
        #expect(Set(icon.pixels.compactMap { $0 }) == [Palette.template])
        // Body is solid, eyes are punched out so the template keeps its face.
        #expect(icon.pixel(9, 14) != nil)
        #expect(icon.pixel(5, 7) == nil)
    }
}

@Suite struct DrainTests {
    @Test func zeroRowsChangesNothing() {
        let idle = SpriteFactory.frames(for: .idle, agentCubes: false)[0]
        #expect(idle.drained(rows: 0) == idle)
    }

    @Test func drainsTopFillRowsButKeepsOutlineAndFace() {
        let idle = SpriteFactory.frames(for: .idle, agentCubes: false)[0]
        let drained = idle.drained(rows: 3)
        // Body top outline is at y=12; rows 13...15 lose their fill, row 16 keeps it.
        #expect(drained.pixel(9, 12) == Palette.outline)
        #expect(drained.pixel(11, 14) == Palette.empty)
        #expect(drained.pixel(10, 15) == Palette.empty)
        #expect(drained.pixel(11, 16) == Palette.fill)
        #expect(drained.pixel(13, 17) == Palette.eye)
    }
}

@Suite struct HomeSpriteTests {
    @Test func burrowedShowsOnlyGlowingEyesInTheHole() {
        for frame in SpriteFactory.frames(for: .burrowed, agentCubes: false) {
            #expect(!frame.pixels.contains(Palette.fill))
            #expect(frame.pixels.contains(Palette.notch))
        }
        let blinks = SpriteFactory.frames(for: .burrowed, agentCubes: false).map { $0.pixels.filter { $0 == Palette.glow }.count }
        #expect(Set(blinks).count > 1)
    }

    @Test func peekHoldIsOutsideTheHole() {
        for frame in SpriteFactory.frames(for: .peekHold, agentCubes: false) {
            #expect(frame.pixels.contains(Palette.fill))
            #expect(frame.pixel(16, 2) == Palette.notch)
        }
    }

    @Test func diveEndsHidden() {
        let frames = SpriteFactory.frames(for: .dive, agentCubes: false)
        #expect(frames.first!.pixels.contains(Palette.fill))
        #expect(!frames.last!.pixels.contains(Palette.fill))
    }

    @Test func appFramesHaveNoPrototypeMenuBarStrips() {
        let peek = SpriteFactory.frames(for: .peek, agentCubes: false)[0]
        #expect(peek.pixel(0, 0) == nil)
        #expect(SpriteFactory.frames(for: .peek)[0].pixel(0, 0) == Palette.menuBar)
    }
}

@Suite struct GazeSpriteTests {
    @Test func gazeMovesTheEyesInIdle() {
        let plain = SpriteFactory.frames(for: .idle, agentCubes: false)[0]
        let right = SpriteFactory.frames(for: .idle, agentCubes: false, gaze: Gaze(x: 1, y: 0))[0]
        // Left eye glint at x=12 normally, one pixel to the right when looking right.
        #expect(plain.pixel(12, 16) == Palette.glint)
        #expect(right.pixel(13, 16) == Palette.glint)
        let up = SpriteFactory.frames(for: .idle, agentCubes: false, gaze: Gaze(x: 0, y: -1))[0]
        #expect(up.pixel(12, 15) == Palette.glint)
    }

    @Test func gazeKeepsBlinks() {
        let blink = SpriteFactory.frames(for: .idle, agentCubes: false, gaze: Gaze(x: 1, y: 0))[11]
        #expect(!blink.pixels.contains(Palette.glint))
    }

    @Test func otherStatesIgnoreGaze() {
        #expect(SpriteFactory.frames(for: .sleep, agentCubes: false, gaze: Gaze(x: 1, y: 0))
            == SpriteFactory.frames(for: .sleep, agentCubes: false))
    }
}

@Suite struct SingleFrameTests {
    @Test func singleFrameMatchesTheFullSet() {
        let gaze = Gaze(x: -1, y: -1)
        let all = SpriteFactory.frames(for: .idle, agentCubes: false, gaze: gaze)
        for i in [0, 11, 23] {
            #expect(SpriteFactory.frame(for: .idle, index: i, agentCubes: false, gaze: gaze) == all[i])
        }
        #expect(SpriteFactory.frame(for: .working, index: 3, agentCubes: false, gaze: gaze)
            == SpriteFactory.frames(for: .working, agentCubes: false)[3])
    }
}
