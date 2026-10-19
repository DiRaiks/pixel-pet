import Foundation
import Testing
@testable import PetCore

@Suite struct HomeGeometryTests {
    let size = PetSize(width: 128, height: 128)
    let external = PetScreen(frame: PetRect(x: 0, y: 0, width: 2560, height: 1440),
                             visible: PetRect(x: 0, y: 60, width: 2560, height: 1355))

    @Test func burrowSitsAtTopCenterOfScreen() {
        let home = HomeGeometry.home(on: external, notch: nil)
        #expect(home == HomeSpot(anchor: PetPoint(x: 1280, y: 1440), hasNotch: false))
        #expect(HomeGeometry.windowOrigin(for: home, size: size) == PetPoint(x: 1280 - 64, y: 1440 - 128))
    }

    @Test func notchCenterIsUsedWhenPresent() {
        let laptop = PetScreen(frame: PetRect(x: -1512, y: 0, width: 1512, height: 982),
                               visible: PetRect(x: -1512, y: 0, width: 1512, height: 944))
        let notch = PetRect(x: -1512 + 662, y: 950, width: 188, height: 32)
        let home = HomeGeometry.home(on: laptop, notch: notch)
        #expect(home == HomeSpot(anchor: PetPoint(x: -1512 + 756, y: 982), hasNotch: true, notchHeight: 32))
    }

    @Test func dropNearAHomeSnapsIntoIt() {
        let home = HomeGeometry.home(on: external, notch: nil)
        // Window top-center 40 pt below and 30 pt right of the anchor: inside the snap radius.
        let near = PetPoint(x: 1280 + 30 - 64, y: 1440 - 40 - 128)
        #expect(HomeGeometry.snapTarget(windowOrigin: near, size: size, homes: [home]) == home)
        let far = PetPoint(x: 1280 - 64, y: 1440 - 200 - 128)
        #expect(HomeGeometry.snapTarget(windowOrigin: far, size: size, homes: [home]) == nil)
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
