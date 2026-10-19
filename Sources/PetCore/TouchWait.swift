import Foundation

/// A hardware key waiting for a touch, read from the system log. While a YubiKey (or another smart card)
/// waits for its button during a GPG operation, macOS's smart-card reader service logs "Time extension
/// received" about three times a second; the messages stop once it is touched or the request gives up.
/// Seen with GnuPG talking to the card through the system's PC/SC; its own CCID driver would bypass it.
public struct TouchWait: Sendable {
    /// Waiting ends this long after the last signal.
    public static let quiet: TimeInterval = 1.2
    /// What the watcher asks `log stream` for, so it gets nothing else.
    public static let predicate = #"process == "usbsmartcardreaderd" AND eventMessage == "Time extension received""#

    private var last: Date?
    private var streak = 0

    public init() {}

    /// One line of `log stream --style ndjson` that says the card waits for a touch.
    public static func isTouchRequest(_ line: String) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              json["eventMessage"] as? String == "Time extension received",
              let process = json["processImagePath"] as? String
        else { return false }
        return process.hasSuffix("usbsmartcardreaderd")
    }

    public mutating func signal(at now: Date) {
        if let last, now.timeIntervalSince(last) <= Self.quiet, now >= last { streak += 1 } else {
            streak = 1
            startedAt = now
        }
        last = now
    }

    /// gpg gives up on the key after about 14 s; a wait this long most likely ended that way, not in a touch.
    public static let likelyTimeout: TimeInterval = 13

    private var startedAt: Date?

    /// Two signals in a row start a wait: a single one can come from a slow card operation. A signal from
    /// "the future" (the clock was set back) counts as stale, so a wait can't get stuck.
    public func isWaiting(now: Date) -> Bool {
        guard let last, streak >= 2 else { return false }
        let age = now.timeIntervalSince(last)
        return age >= -1 && age <= Self.quiet
    }

    /// How long the current (or last) wait has gone on, from its first signal to its last.
    public var duration: TimeInterval {
        guard let startedAt, let last else { return 0 }
        return last.timeIntervalSince(startedAt)
    }

    /// When the current wait ends unless another signal comes.
    public var endsAt: Date? { last.map { $0.addingTimeInterval(Self.quiet) } }
}
