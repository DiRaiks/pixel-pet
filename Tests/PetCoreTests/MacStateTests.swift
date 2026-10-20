import Foundation
import Testing
@testable import PetCore

@Suite struct MacStateTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Only an idle pet changes, and a call beats heat, the network, low power and music, in that order.
    @Test func restReplacesOnlyIdleInPriorityOrder() {
        let all = MacState(headphones: true, music: true, onAir: true, hot: true, lowPower: true, offline: true)
        #expect(all.rest(insteadOf: .idle) == .onAir)
        #expect(MacState(music: true, hot: true, lowPower: true, offline: true).rest(insteadOf: .idle) == .overheated)
        #expect(MacState(music: true, lowPower: true, offline: true).rest(insteadOf: .idle) == .offline)
        #expect(MacState(music: true, lowPower: true).rest(insteadOf: .idle) == .lowPower)
        #expect(MacState(music: true).rest(insteadOf: .idle) == .music)
        #expect(MacState(headphones: true).rest(insteadOf: .idle) == .idle)
        for busy in [PetState.working, .alert, .question, .error, .sleep, .tired, .lowLimit, .exhausted] {
            #expect(all.rest(insteadOf: busy) == busy, "\(busy)")
        }
    }

    /// A click puts the current state away; the next one in line shows, and the dismissed one only comes back
    /// once its condition has ended and started again.
    @Test func clickedAwayStatesStayAwayWhileTheyLast() {
        var mac = MacState(music: true, onAir: true)
        var dismissed = MacDismissals()
        #expect(mac.rest(insteadOf: .idle, skipping: dismissed.states) == .onAir)
        dismissed.dismiss(.onAir)
        #expect(mac.rest(insteadOf: .idle, skipping: dismissed.states) == .music)
        dismissed.dismiss(.music)
        #expect(mac.rest(insteadOf: .idle, skipping: dismissed.states) == .idle)
        // The call is still on: it stays away.
        dismissed.update(with: mac)
        #expect(dismissed.states == [.onAir, .music])
        // The call ends; the next one shows again.
        mac.onAir = false
        dismissed.update(with: mac)
        #expect(dismissed.states == [.music])
        mac.onAir = true
        #expect(mac.rest(insteadOf: .idle, skipping: dismissed.states) == .onAir)
    }

    @Test func headphonesComeAndGo() {
        let on = MacState(headphones: true), off = MacState()
        #expect(MacState.headphonesMoment(from: off, to: on) == .headphonesOn)
        #expect(MacState.headphonesMoment(from: on, to: off) == .headphonesOff)
        #expect(MacState.headphonesMoment(from: on, to: on) == nil)
        #expect(MacState.headphonesMoment(from: nil, to: on) == nil, "not at launch")
    }

    /// A ding isn't music; ten seconds of sound is, and a short pause between tracks doesn't stop it.
    @Test func soundBecomesMusicAfterAWhile() {
        var d = SoundDebounce()
        // (seconds from t0, playing, music expected)
        let steps: [(Double, Bool, Bool)] = [
            (0, true, false), (2, false, false), (3, true, false), (13, true, true),
            (14, false, true), (17, true, true), (20, false, true), (25, false, false),
        ]
        for (at, playing, music) in steps {
            let now = d.update(playing: playing, at: t0.addingTimeInterval(at))
            #expect(now == music, "at \(at) s")
            if at == 0 { #expect(d.nextCheck(after: t0) == t0.addingTimeInterval(10)) }
            if at == 20 { #expect(d.nextCheck(after: t0.addingTimeInterval(20)) == t0.addingTimeInterval(25)) }
        }
    }

    @Test func offlineOnlyAfterAFewSeconds() {
        var d = OfflineDebounce()
        let steps: [(Double, Bool, Bool)] = [(0, false, false), (2, true, false), (3, false, false), (8, false, true), (9, true, false)]
        for (at, online, offline) in steps {
            let now = d.update(online: online, at: t0.addingTimeInterval(at))
            #expect(now == offline, "at \(at) s")
            if at == 0 { #expect(d.nextCheck() == t0.addingTimeInterval(5)) }
        }
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // October 2026: the 23rd is a Friday.
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func partyHatFromFiveOnFriday() {
        #expect(!PartyTime.isOn(at: date(23, 16, 59)))
        #expect(PartyTime.isOn(at: date(23, 17)))
        #expect(PartyTime.isOn(at: date(23, 23, 59)))
        #expect(!PartyTime.isOn(at: date(24, 0, 30)))
        #expect(!PartyTime.isOn(at: date(22, 18)))
        #expect(PartyTime.nextStart(after: date(20, 9)) == date(23, 17))
        #expect(PartyTime.nextStart(after: date(23, 18)) == date(30, 17))
    }

    @Test func batteryFullOnlyWhenItReachesTheTopOnTheAdapter() {
        let charging = PowerReading(percent: 99, onAC: true)
        #expect(PowerReading.becameFull(from: charging, to: PowerReading(percent: 100, onAC: true)))
        #expect(!PowerReading.becameFull(from: PowerReading(percent: 100, onAC: true), to: PowerReading(percent: 100, onAC: true)))
        #expect(!PowerReading.becameFull(from: nil, to: PowerReading(percent: 100, onAC: true)), "not at launch")
        #expect(!PowerReading.becameFull(from: PowerReading(percent: 99, onAC: false), to: PowerReading(percent: 100, onAC: false)))
        #expect(!PowerReading.becameFull(from: PowerReading(percent: nil, onAC: true), to: PowerReading(percent: nil, onAC: true)))
    }

    @Test func themeSwitchPlaysTheMatchingMoment() {
        #expect(ThemeChange.moment(from: false, toDark: true) == .darkMode)
        #expect(ThemeChange.moment(from: true, toDark: false) == .lightMode)
        #expect(ThemeChange.moment(from: true, toDark: true) == nil)
        #expect(ThemeChange.moment(from: nil, toDark: true) == nil, "not at launch")
    }

    @Test func macReactionsAreOnByDefault() {
        #expect(PetConfig().macReactions)
    }
}
