import Foundation
import Testing
@testable import PetCore

@Suite struct TouchWaitTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    static let request = #"{"processImagePath":"/System/Library/CryptoTokenKit/usbsmartcardreaderd.slotd/Contents/MacOS/usbsmartcardreaderd","subsystem":"com.apple.CryptoTokenKit","eventMessage":"Time extension received"}"#

    @Test func recognizesTheCardsTimeExtension() {
        #expect(TouchWait.isTouchRequest(Self.request))
        #expect(!TouchWait.isTouchRequest(#"{"processImagePath":"/usr/libexec/other","eventMessage":"Time extension received"}"#))
        #expect(!TouchWait.isTouchRequest(#"{"processImagePath":"/x/usbsmartcardreaderd","eventMessage":"slot was set up"}"#))
        #expect(!TouchWait.isTouchRequest("Filtering the log data using …"))
    }

    /// The key repeats the extension about three times a second while it waits; a single one is noise.
    @Test func waitsAfterTwoSignalsInARow() {
        var w = TouchWait()
        w.signal(at: at(0))
        #expect(!w.isWaiting(now: at(0.1)))
        w.signal(at: at(0.3))
        #expect(w.isWaiting(now: at(0.4)))
        #expect(w.endsAt == at(0.3 + TouchWait.quiet))
    }

    @Test func endsWhenTheSignalsStop() {
        var w = TouchWait()
        for s in stride(from: 0.0, through: 3.0, by: 0.3) { w.signal(at: at(s)) }
        #expect(w.isWaiting(now: at(3.1)))
        #expect(!w.isWaiting(now: at(3.0 + TouchWait.quiet + 0.01)))
    }

    @Test func aLoneSignalLaterDoesNotRestart() {
        var w = TouchWait()
        w.signal(at: at(0)); w.signal(at: at(0.3))
        w.signal(at: at(10))
        #expect(!w.isWaiting(now: at(10.1)))
    }

    /// The clock set back during a wait must not keep it going forever.
    @Test func signalFromTheFutureIsStale() {
        var w = TouchWait()
        w.signal(at: at(100)); w.signal(at: at(100.3))
        #expect(!w.isWaiting(now: at(90)))
    }

    @Test func durationTellsATimeoutFromATouch() {
        var w = TouchWait()
        for s in stride(from: 0.0, through: 14.0, by: 0.3) { w.signal(at: at(s)) }
        #expect(w.duration >= TouchWait.likelyTimeout)
        var quick = TouchWait()
        for s in stride(from: 0.0, through: 2.0, by: 0.3) { quick.signal(at: at(s)) }
        #expect(quick.duration < TouchWait.likelyTimeout)
    }

    @Test func touchStatesBehave() {
        #expect(PetState.touchKey.loops && PetState.touchKeyHome.loops)
        #expect(!PetState.touchDone.loops)
        #expect(MotionPolicy.stillFrame(for: .touchKey) != nil)
        #expect(MotionPolicy.stillFrame(for: .touchKeyHome) != nil)
    }
}
