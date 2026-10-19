import Foundation

/// Finds a native Codex CLI. The npm `codex` is a Node script, and an app launched from Finder has no
/// Node on its PATH, so only Mach-O binaries count: PATH first, then the copy inside the ChatGPT or Codex app,
/// then the newest standalone release Codex keeps under ~/.codex/packages.
public enum CodexLocator {
    public static var defaultCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"),
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
        ]
    }

    public static var defaultReleases: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/packages/standalone/releases")
    }

    public static func find(path: String? = ProcessInfo.processInfo.environment["PATH"],
                            candidates: [URL] = defaultCandidates, releases: URL = defaultReleases) -> URL? {
        let onPath = (path ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        return (onPath + candidates + newestReleases(in: releases)).first(where: isNativeExecutable)
    }

    /// <releases>/<version>-<arch>/codex, newest version first.
    static func newestReleases(in root: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted { ClaudeLocator.isNewer(version($0), than: version($1)) }
            .map { root.appendingPathComponent("\($0)/codex") }
    }

    private static func version(_ name: String) -> String { String(name.prefix { $0 != "-" }) }

    static func isNativeExecutable(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magic = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        // 64-bit Mach-O (either byte order) or a universal binary.
        return [0xFEEDFACF, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }
}
