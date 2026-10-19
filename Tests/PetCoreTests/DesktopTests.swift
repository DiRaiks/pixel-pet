import Foundation
import Testing
@testable import PetCore

@Suite struct GazeTests {
    let pet = PetPoint(x: 500, y: 500)

    @Test func farCursorIsIgnored() {
        #expect(Gaze.toward(PetPoint(x: 900, y: 500), from: pet) == nil)
    }

    @Test func nearCursorPullsTheEyes() {
        #expect(Gaze.toward(PetPoint(x: 700, y: 500), from: pet) == Gaze(x: 1, y: 0))
        #expect(Gaze.toward(PetPoint(x: 350, y: 500), from: pet) == Gaze(x: -1, y: 0))
        // AppKit y grows upward; looking up is a negative sprite offset.
        #expect(Gaze.toward(PetPoint(x: 500, y: 650), from: pet) == Gaze(x: 0, y: -1))
        #expect(Gaze.toward(PetPoint(x: 650, y: 650), from: pet) == Gaze(x: 1, y: -1))
    }

    @Test func cursorRightOnThePetLooksStraight() {
        #expect(Gaze.toward(PetPoint(x: 510, y: 490), from: pet) == Gaze(x: 0, y: 0))
    }

    @Test func belowDoesNotLookDown() {
        // The sprite has no "look down" pose: the eyes stay level.
        #expect(Gaze.toward(PetPoint(x: 500, y: 300), from: pet) == Gaze(x: 0, y: 0))
    }
}

@Suite struct IdleSleepTests {
    @Test func sleepsOnlyWhenNothingElseIsGoingOn() {
        #expect(PetBrain.restState(mood: .idle, userIdle: 601, sleepAfter: 600) == .sleep)
        #expect(PetBrain.restState(mood: .idle, userIdle: 599, sleepAfter: 600) == .idle)
        #expect(PetBrain.restState(mood: .working, userIdle: 9999, sleepAfter: 600) == .working)
        #expect(PetBrain.restState(mood: .alert, userIdle: 9999, sleepAfter: 600) == .alert)
        #expect(PetBrain.restState(mood: .idle, userIdle: 9999, sleepAfter: 0) == .idle)
    }
}

@Suite struct ReactionThrottleTests {
    @Test func allowsOneReactionPerInterval() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var throttle = ReactionThrottle(interval: 10)
        let first = throttle.take(at: t0)
        let tooSoon = throttle.take(at: t0.addingTimeInterval(5))
        let later = throttle.take(at: t0.addingTimeInterval(10.5))
        #expect(first)
        #expect(!tooSoon)
        #expect(later)
    }
}

@Suite struct FullscreenTests {
    let screen = PetRect(x: 0, y: 0, width: 2560, height: 1440)

    @Test func windowCoveringTheScreenIsFullscreen() {
        #expect(Fullscreen.covers(window: PetRect(x: 0, y: 0, width: 2560, height: 1440), screen: screen))
        #expect(Fullscreen.covers(window: PetRect(x: -1, y: -1, width: 2562, height: 1442), screen: screen))
    }

    @Test func maximizedButNotFullscreenIsNot() {
        #expect(!Fullscreen.covers(window: PetRect(x: 0, y: 60, width: 2560, height: 1355), screen: screen))
    }

    @Test func cgBoundsFlipToAppKit() {
        // CG: origin top-left of the primary screen; AppKit: bottom-left.
        #expect(Fullscreen.appKitRect(cg: PetRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 1440)
            == PetRect(x: 10, y: 1440 - 20 - 50, width: 100, height: 50))
    }

    @Test func configDefaults() throws {
        let old = try JSONDecoder().decode(PetConfig.self, from: Data(#"{"scale":4}"#.utf8))
        #expect(old.desktopReactions)
        #expect(old.sleepAfterMinutes == 10)
    }
}

@Suite struct DesktopEdgeTests {
    @Test func restStateBoundaries() {
        #expect(PetBrain.restState(mood: .idle, userIdle: 600, sleepAfter: 600) == .sleep)
        #expect(PetBrain.restState(mood: .idle, userIdle: 599.9, sleepAfter: 600) == .idle)
    }

    @Test func flipOnSecondaryScreensKeepsNegativeCoordinates() {
        // Secondary display above-left of a 1440 pt tall primary: CG y is negative there.
        let cg = PetRect(x: -1920, y: -1080, width: 800, height: 600)
        #expect(Fullscreen.appKitRect(cg: cg, primaryHeight: 1440) == PetRect(x: -1920, y: 1440 + 1080 - 600, width: 800, height: 600))
    }

    @Test func coversRespectsTolerance() {
        let screen = PetRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Fullscreen.covers(window: PetRect(x: 2, y: 2, width: 96, height: 96), screen: screen))
        #expect(!Fullscreen.covers(window: PetRect(x: 3, y: 0, width: 97, height: 100), screen: screen))
    }

    @Test func sleepAfterIsClamped() throws {
        let negative = try JSONDecoder().decode(PetConfig.self, from: Data(#"{"sleepAfterMinutes":-5}"#.utf8))
        #expect(negative.sleepAfterMinutes == 0)
        let huge = try JSONDecoder().decode(PetConfig.self, from: Data(#"{"sleepAfterMinutes":99999}"#.utf8))
        #expect(huge.sleepAfterMinutes == 24 * 60)
    }
}
