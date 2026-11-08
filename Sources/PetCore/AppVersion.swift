import Foundation

/// Version strings as releases are numbered: `0.3.0`, `0.3.0-beta.1`.
public enum AppVersion {
    /// Numbers and dots, an optional `-` suffix of letters, digits and dots: what a release tag may carry.
    public static func isValid(_ version: String) -> Bool {
        version.range(of: #"^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?$"#, options: .regularExpression) != nil
    }

    /// Whether `version` is newer than `other`, by their numbers (a suffix is ignored). Anything that isn't a
    /// valid version is never newer.
    public static func isNewer(_ version: String, than other: String) -> Bool {
        guard isValid(version), isValid(other) else { return false }
        func numbers(_ v: String) -> [Int] {
            v.split(separator: "-")[0].split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = numbers(version), b = numbers(other)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The release page for a version, where GitHub lists what changed; nil for anything that isn't a version.
    public static func releasePage(_ version: String) -> URL? {
        guard isValid(version) else { return nil }
        return URL(string: "https://github.com/DiRaiks/pixel-pet/releases/tag/v\(version)")
    }
}
