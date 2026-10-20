import Foundation

/// A file dropped on the pet for a quick question. Only what's here goes to Claude, in the message itself:
/// the CLI runs without tools, so it never reads the disk.
public struct Attachment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case text, code, pdf, image }

    public let name: String
    public let kind: Kind
    /// Size on disk.
    public let bytes: Int
    public var pages: Int?
    /// The text sent (for text, code and PDFs), cut to `Attachment.maxText` characters.
    public var text: String?
    public var truncated = false
    /// The picture sent (for images), already scaled down.
    public var image: Data?
    public var mediaType: String?

    public init(name: String, kind: Kind, bytes: Int, pages: Int? = nil, text: String? = nil, truncated: Bool = false,
                image: Data? = nil, mediaType: String? = nil) {
        self.name = name
        self.kind = kind
        self.bytes = bytes
        self.pages = pages
        self.text = text
        self.truncated = truncated
        self.image = image
        self.mediaType = mediaType
    }

    public static let maxFiles = 3
    public static let maxText = 200_000
    /// Longest side of an image sent; larger ones are scaled down (Claude doesn't use more).
    public static let imageSide = 1568
    /// Larger files aren't read at all (text past `maxText` is cut, but reading a huge log is still slow).
    public static let maxFileBytes = 30_000_000

    static let codeExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rb", "go", "rs", "java", "kt", "kts", "c", "h", "cc",
        "cpp", "hpp", "m", "mm", "cs", "php", "sh", "zsh", "bash", "fish", "sql", "sol", "vue", "svelte", "css", "scss",
        "html", "xml", "lua", "dart", "scala", "ex", "exs", "hs", "zig", "tf", "proto", "graphql", "gradle", "r",
    ]
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "json", "jsonl", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "csv",
        "tsv", "log", "plist", "srt", "vtt", "tex", "rtf", "diff", "patch", "lock", "gitignore", "dockerfile", "makefile",
    ]
    static let imageTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
        "heic": "image/heic", "heif": "image/heic", "tiff": "image/tiff", "tif": "image/tiff", "bmp": "image/bmp",
    ]

    /// What a file is, by its name; nil for files the pet can't send (archives, apps, media, folders…).
    /// Files without an extension (Makefile, Dockerfile, LICENSE) count as text if their bytes are text.
    public static func kind(forName name: String) -> Kind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return .text }
        if codeExtensions.contains(ext) { return .code }
        if textExtensions.contains(ext) { return .text }
        if ext == "pdf" { return .pdf }
        if imageTypes[ext] != nil { return .image }
        return nil
    }

    /// UTF-8 text, or nil for binary data (a NUL byte early on, or bytes that aren't UTF-8).
    public static func decodeText(_ data: Data) -> String? {
        if data.prefix(8192).contains(0) { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Cut to `maxText` characters, at a line break when there's one near the end.
    public static func cut(_ text: String) -> (text: String, truncated: Bool) {
        guard text.count > maxText else { return (text, false) }
        let head = String(text.prefix(maxText))
        if let lastBreak = head.lastIndex(of: "\n"), head.distance(from: lastBreak, to: head.endIndex) < 2000 {
            return (String(head[..<lastBreak]), true)
        }
        return (head, true)
    }

    /// The text part of the message: each file in a tagged block, then the question.
    public static func prompt(question: String, files: [Attachment]) -> String {
        let blocks = files.compactMap { file -> String? in
            guard let text = file.text else { return nil }
            let note = file.truncated ? " truncated=\"true\"" : ""
            return "<file name=\"\(escape(file.name))\"\(note)>\n\(text)\n</file>"
        }
        let images = files.filter { $0.image != nil }.map { "<image name=\"\(escape($0.name))\"/>" }
        return (blocks + images + [question]).joined(separator: "\n\n")
    }

    /// The whole message as one `--input-format stream-json` line: text first, then the images.
    public static func streamMessage(question: String, files: [Attachment]) -> Data {
        var content: [[String: Any]] = [["type": "text", "text": prompt(question: question, files: files)]]
        for file in files {
            guard let image = file.image, let type = file.mediaType else { continue }
            content.append(["type": "image", "source": ["type": "base64", "media_type": type,
                                                         "data": image.base64EncodedString()]])
        }
        let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        var data = (try? JSONSerialization.data(withJSONObject: line)) ?? Data()
        data.append(0x0A)
        return data
    }

    public var needsStreamInput: Bool { image != nil }

    private static func escape(_ name: String) -> String {
        name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
