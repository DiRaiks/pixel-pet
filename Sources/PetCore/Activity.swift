import Foundation

/// What kind of app is in front, for what the pet holds while the user stays in it.
public enum AppKind: Sendable, Equatable {
    case game, video, code

    /// From the app's `LSApplicationCategoryType`, or its bundle id for well-known apps that don't say (or say
    /// something else, as Terminal does).
    public static func of(bundleID: String?, category: String?) -> AppKind? {
        if let bundleID {
            if codeApps.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.") { return .code }
            if videoApps.contains(bundleID) { return .video }
        }
        guard let category = category?.lowercased() else { return nil }
        if category == "public.app-category.games" || category.hasSuffix("-games") { return .game }
        if category == "public.app-category.video" || category == "public.app-category.entertainment" { return .video }
        if category == "public.app-category.developer-tools" { return .code }
        return nil
    }

    static let codeApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.sublimetext.4", "com.apple.dt.Xcode",
    ]
    static let videoApps: Set<String> = [
        "com.colliderli.iina", "org.videolan.vlc", "com.apple.QuickTimePlayerX", "com.apple.TV", "com.firecore.infuse",
    ]

    public var rest: PetState {
        switch self {
        case .game: .gamepad
        case .video: .popcorn
        case .code: .coding
        }
    }
}

/// The app in front counts once the user has stayed in it a while: a quick look at a terminal isn't coding.
public struct AppFocus: Sendable {
    public static let settle: TimeInterval = 90

    private var kind: AppKind?
    private var since: Date?

    public init() {}

    /// The frontmost app changed (or was looked at again): the clock restarts only when its kind changes.
    public mutating func update(_ next: AppKind?, at now: Date) {
        guard next != kind else { return }
        kind = next
        since = next == nil ? nil : now
    }

    public func current(at now: Date) -> AppKind? {
        guard let kind, let since, now.timeIntervalSince(since) >= Self.settle else { return nil }
        return kind
    }

    /// When `current` will change without a new update.
    public func nextChange(after now: Date) -> Date? {
        guard kind != nil, let since else { return nil }
        let due = since.addingTimeInterval(Self.settle)
        return due > now ? due : nil
    }
}

/// Typing, from the time since the last key press alone (no keys are read): steady keys for a few seconds
/// start it, a few seconds without any end it.
public struct TypingDetector: Sendable {
    public static let startAfter: TimeInterval = 6
    public static let stopAfter: TimeInterval = 4
    /// A pause between keys that still keeps the streak going.
    public static let gap: TimeInterval = 1.5

    private var streakSince: Date?
    public private(set) var isTyping = false

    public init() {}

    @discardableResult
    public mutating func update(secondsSinceKey: TimeInterval, at now: Date) -> Bool {
        if secondsSinceKey <= Self.gap {
            let since = streakSince ?? now.addingTimeInterval(-secondsSinceKey)
            streakSince = since
            if now.timeIntervalSince(since) >= Self.startAfter { isTyping = true }
        } else {
            streakSince = nil
            if secondsSinceKey >= Self.stopAfter { isTyping = false }
        }
        return isTyping
    }

    public mutating func reset() {
        streakSince = nil
        isTyping = false
    }
}

/// Spaces switching: dizzy after a quick run of them. A single switch shows nothing: macOS hides windows that
/// join all Spaces while it slides, so anything played for it would come late.
public struct SpaceSwitches: Sendable {
    public static let dizzyAfter = 4
    public static let dizzyWindow: TimeInterval = 12
    public static let dizzyEvery: TimeInterval = 120

    private var recent: [Date] = []
    private var lastDizzy: Date?

    public init() {}

    /// A switch happened: what the pet plays for it, if anything.
    public mutating func record(at now: Date) -> PetState? {
        recent = recent.filter { now.timeIntervalSince($0) < Self.dizzyWindow } + [now]
        guard recent.count >= Self.dizzyAfter, lastDizzy.map({ now.timeIntervalSince($0) >= Self.dizzyEvery }) ?? true
        else { return nil }
        lastDizzy = now
        recent.removeAll()
        return .dizzy
    }
}

/// What the user is up to, as the idle pet shows it.
public struct ActivityState: Equatable, Sendable {
    /// The app in front, once it has settled (`AppFocus`).
    public var app: AppKind?
    public var typing = false

    public init(app: AppKind? = nil, typing: Bool = false) {
        self.app = app
        self.typing = typing
    }

    /// Only an idle pet changes. A game or a video holds the eyes even with keys going; typing shows over
    /// code, and code shows when the keys rest.
    public func rest(insteadOf rest: PetState, skipping dismissed: Set<PetState> = []) -> PetState {
        guard rest == .idle else { return rest }
        let order: [PetState] = [.gamepad, .popcorn, .typingAlong, .coding]
        return order.first { isActive($0) && !dismissed.contains($0) } ?? rest
    }

    public func isActive(_ state: PetState) -> Bool {
        switch state {
        case .gamepad: app == .game
        case .popcorn: app == .video
        case .coding: app == .code
        case .typingAlong: typing
        default: false
        }
    }

    public static let rests: Set<PetState> = [.gamepad, .popcorn, .coding, .typingAlong]
}

/// Activity rests the user clicked away: each stays away while it lasts (the same kind of app in front).
/// Typing comes and goes with every pause, so its dismissal lasts until the keys rest for a while.
public struct ActivityDismissals: Sendable {
    public static let typingGrace: TimeInterval = 60

    public private(set) var states: Set<PetState> = []
    private var typingStoppedAt: Date?

    public init() {}

    public mutating func dismiss(_ state: PetState) { states.insert(state) }

    public mutating func update(with activity: ActivityState, at now: Date) {
        if activity.typing {
            typingStoppedAt = nil
        } else if typingStoppedAt == nil {
            typingStoppedAt = now
        }
        states = states.filter { state in
            if activity.isActive(state) { return true }
            guard state == .typingAlong, let stopped = typingStoppedAt else { return false }
            return now.timeIntervalSince(stopped) < Self.typingGrace
        }
    }
}

/// How often the one-offs may play, and what counts.
public enum ActivityTiming {
    /// No launch reactions this long after the app starts or the Mac wakes: login items open in a burst.
    public static let settleAfterStart: TimeInterval = 60
    public static let launchEvery: TimeInterval = 120
    public static let quitEvery: TimeInterval = 120
    /// An app waved goodbye to has been open at least this long.
    public static let longUse: TimeInterval = 30 * 60
    public static let layoutEvery: TimeInterval = 3
    /// A stick that keeps dropping out and coming back doesn't get cheered every time.
    public static let volumeEvery: TimeInterval = 30
    /// A new display is believed once the screen count has stayed up this long.
    public static let displaySettle: TimeInterval = 2

    public static func quitCounts(launchedAt: Date?, at now: Date) -> Bool {
        guard let launchedAt else { return false }
        return now.timeIntervalSince(launchedAt) >= longUse
    }
}

/// The keyboard layout's code for the badge: the input source's first language, two capital letters.
public enum InputSourceCode {
    public static func code(languages: [String]) -> String? {
        guard let first = languages.first else { return nil }
        let letters = first.prefix(2).uppercased()
        guard letters.count == 2, letters.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        return letters
    }
}

/// A volume that counts as a USB stick, a card or an external drive: local, removable or ejectable, not
/// internal, and not a disk image (DiskArbitration's "Virtual Interface") or a network share.
public enum RemovableVolume {
    public static func counts(removable: Bool?, ejectable: Bool?, isInternal: Bool?, isLocal: Bool?,
                              deviceProtocol: String?) -> Bool {
        (removable == true || ejectable == true) && isInternal != true && isLocal != false
            && deviceProtocol != "Virtual Interface"
    }
}
