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

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decodeIfPresent(PetPoint.self, forKey: .origin)
        let rawScale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? 4
        scale = min(max(rawScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        logEvents = try c.decodeIfPresent(Bool.self, forKey: .logEvents) ?? false
        lastLimits = try? c.decodeIfPresent(UsageLimits.self, forKey: .lastLimits)
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
