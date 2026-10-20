import Foundation

/// What the Mac itself is up to, as far as the pet reacts to it.
public struct MacState: Equatable, Sendable {
    /// Sound goes to headphones (Bluetooth, or the built-in jack).
    public var headphones = false
    /// Sound has been playing long enough to count as music (see `SoundDebounce`).
    public var music = false
    /// A microphone or camera is in use by some app.
    public var onAir = false
    /// The thermal state is serious or critical.
    public var hot = false
    public var lowPower = false
    /// No network path (debounced, see `OfflineDebounce`).
    public var offline = false

    public init(headphones: Bool = false, music: Bool = false, onAir: Bool = false, hot: Bool = false,
                lowPower: Bool = false, offline: Bool = false) {
        self.headphones = headphones
        self.music = music
        self.onAir = onAir
        self.hot = hot
        self.lowPower = lowPower
        self.offline = offline
    }

    /// What the pet does instead of plain idling. Only an idle pet changes: agents, alerts, sleep and calls
    /// keep their own states. A call (mic or camera) comes first, then heat, then the network, low power, and
    /// music last: sound during a call is the call.
    public func rest(insteadOf rest: PetState) -> PetState {
        guard rest == .idle else { return rest }
        if onAir { return .onAir }
        if hot { return .overheated }
        if offline { return .offline }
        if lowPower { return .lowPower }
        if music { return .music }
        return rest
    }

    /// The one-shot for a change in headphones: on when they connect, off when they go.
    public static func headphonesMoment(from old: MacState?, to new: MacState) -> PetState? {
        guard let old, old.headphones != new.headphones else { return nil }
        return new.headphones ? .headphonesOn : .headphonesOff
    }
}

/// Sound that keeps playing for a while is music; a notification ding isn't. And a pause between tracks
/// doesn't stop the dancing.
public struct SoundDebounce: Sendable {
    public static let startAfter: TimeInterval = 10
    public static let stopAfter: TimeInterval = 5

    private var playingSince: Date?
    private var silentSince: Date?
    public private(set) var isMusic = false

    public init() {}

    /// Feed the raw "output is running" flag; returns whether it counts as music now.
    @discardableResult
    public mutating func update(playing: Bool, at now: Date) -> Bool {
        if playing {
            silentSince = nil
            if playingSince == nil { playingSince = now }
            if let since = playingSince, now.timeIntervalSince(since) >= Self.startAfter { isMusic = true }
        } else {
            playingSince = nil
            if silentSince == nil { silentSince = now }
            if let since = silentSince, now.timeIntervalSince(since) >= Self.stopAfter { isMusic = false }
        }
        return isMusic
    }

    /// When to look again for a change that happens without a new event.
    public func nextCheck(after now: Date) -> Date? {
        if !isMusic, let since = playingSince { return since.addingTimeInterval(Self.startAfter) }
        if isMusic, let since = silentSince { return since.addingTimeInterval(Self.stopAfter) }
        return nil
    }
}

/// The network flaps around sleep, wake and Wi-Fi roaming: only a few seconds without a path count.
public struct OfflineDebounce: Sendable {
    public static let after: TimeInterval = 5

    private var lostAt: Date?
    public private(set) var isOffline = false

    public init() {}

    @discardableResult
    public mutating func update(online: Bool, at now: Date) -> Bool {
        if online {
            lostAt = nil
            isOffline = false
        } else {
            if lostAt == nil { lostAt = now }
            if let lost = lostAt, now.timeIntervalSince(lost) >= Self.after { isOffline = true }
        }
        return isOffline
    }

    public func nextCheck() -> Date? {
        guard !isOffline, let lostAt else { return nil }
        return lostAt.addingTimeInterval(Self.after)
    }
}

/// Friday evening: a party hat from 17:00 to midnight, by the Mac's clock.
public enum PartyTime {
    public static let startHour = 17

    public static func isOn(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour], from: date)
        return c.weekday == 6 && (c.hour ?? 0) >= startHour
    }

    /// The next Friday 17:00 after `date` (midnight is already redrawn for the daily look).
    public static func nextStart(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: startHour, minute: 0, second: 0, weekday: 6),
                          matchingPolicy: .nextTime)
    }
}

extension PowerReading {
    /// Charged to the top while on the adapter; never at launch.
    public static func becameFull(from old: PowerReading?, to new: PowerReading) -> Bool {
        guard let old, let before = old.percent, let now = new.percent else { return false }
        return new.onAC && before < 100 && now >= 100
    }
}

/// The system appearance switched; nil when it didn't (or at launch).
public enum ThemeChange {
    public static func moment(from old: Bool?, toDark dark: Bool) -> PetState? {
        guard let old, old != dark else { return nil }
        return dark ? .darkMode : .lightMode
    }
}
