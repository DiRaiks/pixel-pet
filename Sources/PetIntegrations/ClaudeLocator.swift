import Foundation

/// Finds the Claude Code CLI: an explicit path, then PATH, then the newest copy bundled with Claude desktop.
public enum ClaudeLocator {
    public static var defaultAppSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code")
    }

    public static func find(override: String? = nil,
                            path: String? = ProcessInfo.processInfo.environment["PATH"],
                            appSupport: URL = defaultAppSupport) -> URL? {
        let fm = FileManager.default
        if let override, fm.isExecutableFile(atPath: override) { return URL(fileURLWithPath: override) }
        for dir in (path ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("claude")
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return newestBundled(in: appSupport)
    }

    /// Layout: <appSupport>/<version>/<hash>/claude.app/Contents/MacOS/claude
    static func newestBundled(in root: URL) -> URL? {
        let fm = FileManager.default
        let versions = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        for version in versions.sorted(by: { isNewer($0, than: $1) }) {
            let versionDir = root.appendingPathComponent(version)
            for hash in (try? fm.contentsOfDirectory(atPath: versionDir.path)) ?? [] {
                let binary = versionDir.appendingPathComponent("\(hash)/claude.app/Contents/MacOS/claude")
                if fm.isExecutableFile(atPath: binary.path) { return binary }
            }
        }
        return nil
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
