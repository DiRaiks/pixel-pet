import Foundation
import Testing
@testable import PetCore

@Suite struct HomeGeometryTests {
    let size = PetSize(width: 128, height: 128)
    let external = PetScreen(frame: PetRect(x: 0, y: 0, width: 2560, height: 1440),
                             visible: PetRect(x: 0, y: 60, width: 2560, height: 1355))

    @Test func burrowSitsAtTopCenterOfScreen() {
        let home = HomeGeometry.home(on: external, notch: nil)
        #expect(home == HomeSpot(anchor: PetPoint(x: 1280, y: 1440), hasNotch: false, edge: 0...2560))
        #expect(HomeGeometry.windowOrigin(for: home, size: size) == PetPoint(x: 1280 - 64, y: 1440 - 128))
    }

    @Test func notchCenterIsUsedWhenPresent() {
        let laptop = PetScreen(frame: PetRect(x: -1512, y: 0, width: 1512, height: 982),
                               visible: PetRect(x: -1512, y: 0, width: 1512, height: 944))
        let notch = PetRect(x: -1512 + 662, y: 950, width: 188, height: 32)
        let home = HomeGeometry.home(on: laptop, notch: notch)
        #expect(home == HomeSpot(anchor: PetPoint(x: -1512 + 756, y: 982), hasNotch: true, notchHeight: 32, edge: -1512...0))
    }

    @Test func dropNearAHomeSnapsIntoIt() {
        let home = HomeGeometry.home(on: external, notch: nil)
        // Window top-center 40 pt below and 30 pt right of the anchor: inside the snap radius.
        let near = PetPoint(x: 1280 + 30 - 64, y: 1440 - 40 - 128)
        #expect(HomeGeometry.snapTarget(windowOrigin: near, size: size, homes: [home]) == home)
        let far = PetPoint(x: 1280 - 64, y: 1440 - 200 - 128)
        #expect(HomeGeometry.snapTarget(windowOrigin: far, size: size, homes: [home]) == nil)
    }

    /// Anywhere along the top edge of a screen counts: the pet slides over into that screen's home.
    @Test func dropAnywhereAlongTheTopEdgeGoesHome() {
        let home = HomeGeometry.home(on: external, notch: nil)
        let farLeft = PetPoint(x: 120, y: 1440 - 128 + 20)
        #expect(HomeGeometry.snapTarget(windowOrigin: farLeft, size: size, homes: [home]) == home)
        let farRight = PetPoint(x: 2560 - 128, y: 1440 - 128 - 40)
        #expect(HomeGeometry.snapTarget(windowOrigin: farRight, size: size, homes: [home]) == home)
        // Held by the middle with the cursor pinned at the top of the screen, the window pokes far above the edge.
        let heldUp = PetPoint(x: 300, y: 1440 - 128 + 100)
        #expect(HomeGeometry.snapTarget(windowOrigin: heldUp, size: size, homes: [home]) == home)
        // Well below the edge it stays on the desk.
        let lower = PetPoint(x: 120, y: 1440 - 128 - 150)
        #expect(HomeGeometry.snapTarget(windowOrigin: lower, size: size, homes: [home]) == nil)
    }

    /// The edge band belongs to its own screen: a pet at the top of the left screen doesn't fly to the right one.
    @Test func topEdgeBandStaysOnItsScreen() {
        let left = HomeGeometry.home(on: external, notch: nil)
        let right = HomeGeometry.home(on: PetScreen(frame: PetRect(x: 2560, y: -196, width: 1920, height: 1080),
                                                     visible: PetRect(x: 2560, y: -196, width: 1920, height: 1080)), notch: nil)
        let topOfRight = PetPoint(x: 2560 + 100, y: 884 - 128 + 10)
        #expect(HomeGeometry.snapTarget(windowOrigin: topOfRight, size: size, homes: [left, right]) == right)
        // Below the right screen's top but level with the left screen's band is nowhere near a home.
        let besideRight = PetPoint(x: 2560 + 100, y: 1440 - 128 - 10)
        #expect(HomeGeometry.snapTarget(windowOrigin: besideRight, size: size, homes: [left, right]) == nil)
    }

    /// Pulling the pet out of its home must not need a long drag: a short tug lands it on the desk,
    /// and only letting go almost where it sat puts it back.
    @Test func pullingOutOfHomeNeedsOnlyAShortTug() {
        let home = HomeGeometry.home(on: external, notch: nil)
        let seat = HomeGeometry.windowOrigin(for: home, size: size)
        let tugged = PetPoint(x: seat.x, y: seat.y - 50)
        #expect(HomeGeometry.snapTarget(windowOrigin: tugged, size: size, homes: [home]) == home, "from the desk it would snap")
        #expect(HomeGeometry.snapTarget(windowOrigin: tugged, size: size, homes: [home], leaving: home) == nil)
        let barelyMoved = PetPoint(x: seat.x + 10, y: seat.y - 12)
        #expect(HomeGeometry.snapTarget(windowOrigin: barelyMoved, size: size, homes: [home], leaving: home) == home)
    }

    /// Under a notch the seat itself hangs below the anchor; leaving is measured from the seat, not the anchor.
    @Test func leavingANotchHomeIsMeasuredFromItsSeat() {
        let notch = PetRect(x: 1180, y: 1408, width: 200, height: 32)
        let home = HomeGeometry.home(on: external, notch: notch)
        let seat = HomeGeometry.windowOrigin(for: home, size: size)
        #expect(HomeGeometry.snapTarget(windowOrigin: seat, size: size, homes: [home], leaving: home) == home)
        let tugged = PetPoint(x: seat.x, y: seat.y - 40)
        #expect(HomeGeometry.snapTarget(windowOrigin: tugged, size: size, homes: [home], leaving: home) == nil)
    }

    /// Carried from one home over to another screen's home: that one still pulls it in with the full radius.
    @Test func anotherHomeStillSnapsWhileLeavingOne() {
        let a = HomeSpot(anchor: PetPoint(x: 400, y: 1000), hasNotch: false)
        let b = HomeSpot(anchor: PetPoint(x: 1400, y: 1000), hasNotch: false)
        let nearB = PetPoint(x: 1400 + 40 - 64, y: 1000 - 50 - 128)
        #expect(HomeGeometry.snapTarget(windowOrigin: nearB, size: size, homes: [a, b], leaving: a) == b)
    }

    @Test func nearestHomeWinsAcrossScreens() {
        let a = HomeSpot(anchor: PetPoint(x: 100, y: 1000), hasNotch: false)
        let b = HomeSpot(anchor: PetPoint(x: 160, y: 1000), hasNotch: false)
        let origin = PetPoint(x: 150 - 64, y: 1000 - 128)
        #expect(HomeGeometry.snapTarget(windowOrigin: origin, size: size, homes: [a, b]) == b)
    }
}

@Suite struct HomeBrainTests {
    @Test func quietHomeStaysBurrowed() {
        for state in [PetState.idle, .working, .lowLimit, .sleep] {
            #expect(PetBrain.homeState(for: state, doNotDisturb: false) == .burrowed, "\(state)")
        }
    }

    @Test func alertsAndErrorsPeekOut() {
        #expect(PetBrain.homeState(for: .alert, doNotDisturb: false) == .peekHold)
        #expect(PetBrain.homeState(for: .error, doNotDisturb: false) == .peekHold)
    }

    @Test func doNotDisturbOnlyLetsErrorsThrough() {
        #expect(PetBrain.homeState(for: .alert, doNotDisturb: true) == .burrowed)
        #expect(PetBrain.homeState(for: .error, doNotDisturb: true) == .peekHold)
    }

    @Test func homeReactions() {
        #expect(PetBrain.homeReaction(to: .celebrate, doNotDisturb: false) == .peek)
        #expect(PetBrain.homeReaction(to: .celebrate, doNotDisturb: true) == nil)
        #expect(PetBrain.homeReaction(to: .hop, doNotDisturb: false) == .peek)
    }
}

@Suite struct HomeConfigTests {
    @Test func oldConfigsDecodeWithDeskDefaults() throws {
        let config = try JSONDecoder().decode(PetConfig.self, from: Data(#"{"scale":4}"#.utf8))
        #expect(config.isHome == false)
        #expect(config.doNotDisturb == false)
        #expect(config.homeDisplay == nil)
    }

    @Test func homeFieldsRoundTrip() throws {
        var config = PetConfig()
        config.isHome = true
        config.doNotDisturb = true
        config.homeDisplay = 69_733_382
        let back = try JSONDecoder().decode(PetConfig.self, from: JSONEncoder().encode(config))
        #expect(back == config)
    }
}

@Suite struct NotchGeometryTests {
    let laptop = PetRect(x: -1512, y: 0, width: 1512, height: 982)

    @Test func globalAuxiliaryAreasGiveTheGap() {
        let left = PetRect(x: -1512, y: 950, width: 662, height: 32)
        let right = PetRect(x: -662, y: 950, width: 662, height: 32)
        #expect(HomeGeometry.notch(screen: laptop, left: left, right: right, safeTop: 32)
            == PetRect(x: -850, y: 950, width: 188, height: 32))
    }

    @Test func screenLocalAuxiliaryAreasAreMovedOntoTheScreen() {
        let left = PetRect(x: 0, y: 950, width: 662, height: 32)
        let right = PetRect(x: 850, y: 950, width: 662, height: 32)
        #expect(HomeGeometry.notch(screen: laptop, left: left, right: right, safeTop: 32)
            == PetRect(x: -850, y: 950, width: 188, height: 32))
    }

    @Test func noNotchCases() {
        let left = PetRect(x: -1512, y: 950, width: 662, height: 32)
        let right = PetRect(x: -662, y: 950, width: 662, height: 32)
        #expect(HomeGeometry.notch(screen: laptop, left: left, right: right, safeTop: 0) == nil)
        #expect(HomeGeometry.notch(screen: laptop, left: nil, right: right, safeTop: 32) == nil)
        #expect(HomeGeometry.notch(screen: laptop, left: right, right: left, safeTop: 32) == nil)
    }

    @Test func underANotchTheEyesSitJustBelowIt() {
        let notch = PetRect(x: -850, y: 950, width: 188, height: 32)
        let home = HomeGeometry.home(on: PetScreen(frame: laptop, visible: laptop), notch: notch)
        #expect(home.notchHeight == 32)
        // Scale 4: eyes start one sprite pixel (4 pt) below the window top, so the window drops 32 - 4 pt.
        let origin = HomeGeometry.windowOrigin(for: home, size: PetSize(width: 128, height: 128))
        #expect(origin == PetPoint(x: -756 - 64, y: 982 - 128 - 28))
    }

    @Test func flickTowardHomeSnaps() {
        let home = HomeSpot(anchor: PetPoint(x: 1280, y: 1440), hasNotch: false)
        let size = PetSize(width: 128, height: 128)
        let start = PetPoint(x: 1280 - 64, y: 1440 - 128 - 300)
        #expect(HomeGeometry.snapTarget(windowOrigin: start, size: size, homes: [home]) == nil)
        let landing = PetPoint(x: start.x, y: start.y + 2500 * Placement.throwTime)
        #expect(HomeGeometry.snapTarget(windowOrigin: landing, size: size, homes: [home]) == home)
    }
}
