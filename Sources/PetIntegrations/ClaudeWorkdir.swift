import Foundation

/// Where the pet runs its own `claude -p`, and the folders Claude Code keeps those sessions in, so the pet
/// removes exactly those and never a project of yours that happens to have a similar name.
public enum ClaudeWorkdir {
    public static var url: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-claude", isDirectory: true)
    }

    /// Where older builds ran the limits probe; their sessions are cleaned up too.
    static var legacyProbe: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-probe", isDirectory: true)
    }

    /// The `~/.claude/projects` folder name Claude Code uses for sessions run in `path`: every character
    /// other than an ASCII letter or digit becomes "-".
    public static func projectFolderName(forPath path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return String(trimmed.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar)) ? Character(scalar) : "-"
        })
    }

    /// The pet's session folders: for each workdir, its path as given and with symlinks resolved
    /// (`/var` is `/private/var` on macOS, and the CLI sees the resolved one).
    public static var sessionFolderNames: Set<String> {
        var names = Set<String>()
        for dir in [url, legacyProbe] {
            names.insert(projectFolderName(forPath: dir.path))
            if let real = realpath(dir.path, nil) {
                names.insert(projectFolderName(forPath: String(cString: real)))
                free(real)
            }
        }
        return names
    }
}
