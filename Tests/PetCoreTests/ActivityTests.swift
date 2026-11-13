import Foundation
import Testing
@testable import PetCore

@Suite struct ActivityTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func appKindsFromCategoryAndBundle() {
        #expect(AppKind.of(bundleID: "com.example.game", category: "public.app-category.action-games") == .game)
        #expect(AppKind.of(bundleID: nil, category: "public.app-category.games") == .game)
        #expect(AppKind.of(bundleID: "com.colliderli.iina", category: nil) == .video)
        #expect(AppKind.of(bundleID: nil, category: "public.app-category.video") == .video)
        #expect(AppKind.of(bundleID: "com.apple.Terminal", category: "public.app-category.utilities") == .code)
        #expect(AppKind.of(bundleID: "com.jetbrains.goland", category: nil) == .code)
        #expect(AppKind.of(bundleID: nil, category: "public.app-category.developer-tools") == .code)
        #expect(AppKind.of(bundleID: "com.apple.Safari", category: "public.app-category.productivity") == nil)
        #expect(AppKind.of(bundleID: nil, category: nil) == nil)
        #expect(AppKind.game.rest == .gamepad && AppKind.video.rest == .popcorn && AppKind.code.rest == .coding)
    }

    /// A quick look at a terminal isn't coding: the kind counts after a while in front, and switching between
    /// two apps of the same kind doesn't restart the clock.
    @Test func appFocusSettles() {
        var focus = AppFocus()
        focus.update(.code, at: t0)
        #expect(focus.current(at: at(30)) == nil)
        #expect(focus.nextChange(after: at(30)) == at(AppFocus.settle))
        focus.update(.code, at: at(60))
        #expect(focus.current(at: at(AppFocus.settle)) == .code)
        #expect(focus.nextChange(after: at(AppFocus.settle)) == nil)
        focus.update(nil, at: at(200))
        #expect(focus.current(at: at(500)) == nil)
        focus.update(.game, at: at(500))
        #expect(focus.current(at: at(500 + AppFocus.settle - 1)) == nil)
    }

    /// Steady keys for a few seconds start it; a short pause keeps it; a longer one ends it.
    @Test func typingNeedsAStreak() {
        var typing = TypingDetector()
        do { let r = typing.update(secondsSinceKey: 0.2, at: t0); #expect(!r) }
        do { let r = typing.update(secondsSinceKey: 0.8, at: at(3)); #expect(!r) }
        do { let r = typing.update(secondsSinceKey: 0.1, at: at(6.5)); #expect(r) }
        // A pause under the stop time keeps it, though the streak starts over.
        do { let r = typing.update(secondsSinceKey: 2.5, at: at(9)); #expect(r) }
        do { let r = typing.update(secondsSinceKey: 4.5, at: at(11)); #expect(!r) }
        // A single key now and then never starts it.
        var pecking = TypingDetector()
        for k in 0..<10 {
            let r = pecking.update(secondsSinceKey: k % 3 == 0 ? 0.3 : 3, at: at(Double(k) * 2))
            #expect(!r)
        }
    }

    /// A single switch shows nothing; a quick run of them makes it dizzy, at most every two minutes.
    @Test func spaceSwitches() {
        var spaces = SpaceSwitches()
        for s in [0.0, 10, 40, 42, 44] {
            let r = spaces.record(at: at(s))
            #expect(r == nil, "\(s)")
        }
        do { let r = spaces.record(at: at(46)); #expect(r == .dizzy) }
        for k in 0..<4 {
            let r = spaces.record(at: at(50 + Double(k)))
            #expect(r == nil)
        }
        for k in 0..<3 { _ = spaces.record(at: at(170 + Double(k))) }
        do { let r = spaces.record(at: at(173)); #expect(r == .dizzy) }
    }

    /// Only an idle pet changes; a game or video beats typing, typing beats code; clicked away, the next one
    /// in line shows until the condition ends.
    @Test func activityRestOrder() {
        var activity = ActivityState(app: .code, typing: true)
        #expect(activity.rest(insteadOf: .idle) == .typingAlong)
        #expect(activity.rest(insteadOf: .working) == .working)
        activity.typing = false
        #expect(activity.rest(insteadOf: .idle) == .coding)
        activity = ActivityState(app: .game, typing: true)
        #expect(activity.rest(insteadOf: .idle) == .gamepad)
        var dismissed = ActivityDismissals()
        dismissed.dismiss(.gamepad)
        #expect(activity.rest(insteadOf: .idle, skipping: dismissed.states) == .typingAlong)
        dismissed.update(with: activity, at: t0)
        #expect(dismissed.states == [.gamepad])
        activity.app = .video
        dismissed.update(with: activity, at: t0)
        #expect(dismissed.states.isEmpty)
        #expect(activity.rest(insteadOf: .idle, skipping: dismissed.states) == .popcorn)
        #expect(ActivityState().rest(insteadOf: .idle) == .idle)
    }

    /// Typing clicked away stays away through the pauses of a typing session, and comes back after a real
    /// break from the keys.
    @Test func typingDismissalOutlastsPauses() {
        var dismissed = ActivityDismissals()
        var activity = ActivityState(typing: true)
        dismissed.dismiss(.typingAlong)
        dismissed.update(with: activity, at: t0)
        activity.typing = false
        dismissed.update(with: activity, at: at(5))
        activity.typing = true
        dismissed.update(with: activity, at: at(20))
        #expect(activity.rest(insteadOf: .idle, skipping: dismissed.states) == .idle)
        activity.typing = false
        dismissed.update(with: activity, at: at(30))
        dismissed.update(with: activity, at: at(30 + ActivityDismissals.typingGrace - 1))
        #expect(dismissed.states == [.typingAlong])
        dismissed.update(with: activity, at: at(30 + ActivityDismissals.typingGrace))
        #expect(dismissed.states.isEmpty)
    }

    /// A throttle can be asked without using it up, for reactions that may not get to play.
    @Test func throttleAllowsWithoutTaking() {
        var throttle = ReactionThrottle(interval: 10)
        #expect(throttle.allows(at: t0))
        #expect(throttle.allows(at: t0))
        throttle.mark(at: t0)
        #expect(!throttle.allows(at: at(5)))
        #expect(throttle.allows(at: at(10)))
        let first = throttle.take(at: at(10)), second = throttle.take(at: at(15))
        #expect(first && !second)
    }

    @Test func quitsOnlyAfterLongUse() {
        #expect(!ActivityTiming.quitCounts(launchedAt: nil, at: t0))
        #expect(!ActivityTiming.quitCounts(launchedAt: at(-600), at: t0))
        #expect(ActivityTiming.quitCounts(launchedAt: at(-ActivityTiming.longUse), at: t0))
    }

    @Test func layoutCodes() {
        #expect(InputSourceCode.code(languages: ["en", "en-US"]) == "EN")
        #expect(InputSourceCode.code(languages: ["ru"]) == "RU")
        #expect(InputSourceCode.code(languages: ["zh-Hans"]) == "ZH")
        #expect(InputSourceCode.code(languages: []) == nil)
        #expect(InputSourceCode.code(languages: ["x"]) == nil)
        #expect(InputSourceCode.code(languages: ["ру"]) == nil)
    }

    /// Sticks, cards and external drives count; disk images, network shares and internal disks don't.
    @Test func removableVolumes() {
        func counts(_ removable: Bool?, _ ejectable: Bool?, inside: Bool? = false, local: Bool? = true,
                    _ proto: String? = "USB") -> Bool {
            RemovableVolume.counts(removable: removable, ejectable: ejectable, isInternal: inside, isLocal: local,
                                   deviceProtocol: proto)
        }
        #expect(counts(true, true))
        #expect(counts(false, true))
        #expect(counts(true, nil, inside: nil, local: nil, nil))
        #expect(!counts(false, true, "Virtual Interface"))
        #expect(!counts(true, true, inside: true))
        #expect(!counts(false, true, local: false, nil))
        #expect(!counts(false, false))
        #expect(!counts(nil, nil))
    }
}
