import Foundation

public struct PetConfig: Codable, Equatable, Sendable {
    public static let scaleRange = 2...6

    /// Window origin in global screen coordinates; nil until the user moves the pet.
    public var origin: PetPoint?
    public var scale = 4
    public var isHidden = false
    /// Opt-in debug log of hook events (ids and event names only) in ~/.pixelpet/events.log.
    public var logEvents = false
    /// Last known limits, so the panel isn't blank right after a restart.
    public var lastLimits: UsageLimits?
    /// Living in the notch or burrow rather than on the desk.
    public var isHome = false
    /// Display (CGDirectDisplayID) of the home; nil means the screen with the menu bar.
    public var homeDisplay: UInt32?
    /// Stay home and only come out for errors.
    public var doNotDisturb = false
    /// Translation: text in your language goes to `foreignLanguage`, anything else into `nativeLanguage`.
    public var nativeLanguage = "ru"
    public var foreignLanguage = "en"
    /// Model for quick questions (⌃⌥K).
    public var askModel = "haiku"
    /// Eyes follow the cursor, glances at newly focused windows, dimming over fullscreen apps.
    public var desktopReactions = true
    /// Doze off after this many minutes without input (0 = never).
    public var sleepAfterMinutes = 10
    /// The welcome window has been seen.
    public var onboarded = false
    /// Look: color skin and an optional accessory (see PetSprites `Skin` / `Accessory`).
    public var skin = "lavender"
    public var accessory = "none"
    /// Follow Codex sessions (~/.codex/sessions) next to Claude Code's.
    public var watchCodex = true
    /// Show when a hardware key (YubiKey) waits for a touch, read from the system log.
    public var touchHint = true
    /// Hookah breaks: now and then as an idle fidget, and sometimes after a big finished task.
    public var hookah = true
    /// Get ready for calls from the Mac's calendars (asks for calendar access when turned on).
    public var meetingAlerts = false
    /// Last known Codex limits, like `lastLimits` for Claude.
    public var lastCodexLimits: UsageLimits?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decodeIfPresent(PetPoint.self, forKey: .origin)
        let rawScale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? 4
        scale = min(max(rawScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        logEvents = try c.decodeIfPresent(Bool.self, forKey: .logEvents) ?? false
        lastLimits = try? c.decodeIfPresent(UsageLimits.self, forKey: .lastLimits)
        isHome = try c.decodeIfPresent(Bool.self, forKey: .isHome) ?? false
        homeDisplay = try c.decodeIfPresent(UInt32.self, forKey: .homeDisplay)
        doNotDisturb = try c.decodeIfPresent(Bool.self, forKey: .doNotDisturb) ?? false
        nativeLanguage = try c.decodeIfPresent(String.self, forKey: .nativeLanguage) ?? "ru"
        foreignLanguage = try c.decodeIfPresent(String.self, forKey: .foreignLanguage) ?? "en"
        askModel = try c.decodeIfPresent(String.self, forKey: .askModel) ?? "haiku"
        desktopReactions = try c.decodeIfPresent(Bool.self, forKey: .desktopReactions) ?? true
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? "lavender"
        accessory = try c.decodeIfPresent(String.self, forKey: .accessory) ?? "none"
        watchCodex = try c.decodeIfPresent(Bool.self, forKey: .watchCodex) ?? true
        touchHint = try c.decodeIfPresent(Bool.self, forKey: .touchHint) ?? true
        hookah = try c.decodeIfPresent(Bool.self, forKey: .hookah) ?? true
        meetingAlerts = try c.decodeIfPresent(Bool.self, forKey: .meetingAlerts) ?? false
        lastCodexLimits = try? c.decodeIfPresent(UsageLimits.self, forKey: .lastCodexLimits)
        sleepAfterMinutes = min(max(try c.decodeIfPresent(Int.self, forKey: .sleepAfterMinutes) ?? 10, 0), 24 * 60)
    }
}

/// Reads and writes ~/.pixelpet/config.json. A missing or broken file falls back to defaults.
public struct ConfigStore: Sendable {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelpet/config.json")
    }

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public func load() -> PetConfig {
        guard let data = try? Data(contentsOf: url) else { return PetConfig() }
        if let config = try? JSONDecoder().decode(PetConfig.self, from: data) { return config }
        // Keep the unreadable file next to the new one instead of silently overwriting it on the next save.
        let backup = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return PetConfig()
    }

    public func save(_ config: PetConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
