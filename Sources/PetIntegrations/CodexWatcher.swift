import CoreServices
import Foundation
import PetCore

/// Follows Codex session files (`~/.codex/sessions/**/rollout-*.jsonl`) as Codex appends to them, for every
/// Codex surface at once: CLI, IDE extension and the desktop app all write there.
///
/// Files grow to megabytes, so a file is never read whole once it is big: at start (and for files that
/// show up later) only its first line (the session's metadata) and its last `tailBytes` are read, and after
/// that only the new bytes, again capped to the tail. Runs on its own serial queue; `handler` is called there.
///
/// FSEvents finds new and newly touched files, but it goes quiet about a file that stays open for writing,
/// and Codex keeps its session file open for the whole session. So every followed file also gets a kqueue
/// source (`extend` / `write`), which fires on each append.
/// `~/.codex` is never created or changed: without Codex the watcher waits for the folder to appear.
public final class CodexWatcher: @unchecked Sendable {
    public struct Batch: Sendable {
        public let outputs: [CodexRollout.Output]
        /// Catching up with what was there before: history, not news to react to.
        public let isReplay: Bool
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    /// Enough tail to find the turn that is running now.
    static let tailBytes = 512 << 10
    /// The first line is the session's metadata; it embeds the system prompt, so it can be long.
    static let headBytes = 1 << 20
    /// Lines longer than this are dropped (a huge tool output), so a bad file can't eat memory.
    static let maxLine = 4 << 20
    /// How often to look for `~/.codex/sessions` when Codex isn't installed (yet).
    static let rootRetry: TimeInterval = 60
    /// Followed files beyond this many (the least recently written first) are let go.
    static let maxFollowed = 32
    /// A file left alone this long is let go; a still-open Codex file would no longer be noticed by FSEvents,
    /// so this is long.
    static let forgetAfter: TimeInterval = 24 * 60 * 60

    private struct Tracked {
        var rollout: CodexRollout
        var offset: UInt64
        var pending = Data()
        var touched: Date
        /// kqueue watch on the file; nil for skipped (subagent) files.
        var source: DispatchSourceFileSystemObject?
    }

    private let root: URL
    private let recentWindow: TimeInterval
    private let handler: @Sendable (Batch) -> Void
    private let queue = DispatchQueue(label: "dev.pixelpet.codex")
    private let cancelLock = NSLock()
    private var cancelledFlag = false
    // Touched only on `queue`.
    private var stream: FSEventStreamRef?
    private var retry: DispatchSourceTimer?
    private var files: [String: Tracked] = [:]

    public init(root: URL = CodexWatcher.defaultRoot, recentWindow: TimeInterval = SessionRegistry.staleAfter,
                handler: @escaping @Sendable (Batch) -> Void) {
        self.root = root
        self.recentWindow = recentWindow
        self.handler = handler
    }

    /// Checked between files and before every callback, so `stop()` never waits for a long catch-up.
    private var isCancelled: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelledFlag
    }

    public func start() {
        queue.async { [self] in
            guard stream == nil, retry == nil, !isCancelled else { return }
            begin()
        }
    }

    /// No callbacks reach `handler` once this returns.
    public func stop() {
        cancelLock.lock()
        cancelledFlag = true
        cancelLock.unlock()
        queue.sync {
            retry?.cancel()
            retry = nil
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
            files.values.forEach { $0.source?.cancel() }
            files.removeAll()
        }
    }

    private func begin() {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            waitForRoot()
            return
        }
        startStream()
        catchUp()
    }

    private func waitForRoot() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.rootRetry, repeating: Self.rootRetry, leeway: .seconds(10))
        timer.setEventHandler { [weak self] in
            guard let self, !isCancelled, FileManager.default.fileExists(atPath: root.path) else { return }
            retry?.cancel()
            retry = nil
            begin()
        }
        retry = timer
        timer.resume()
    }

    // MARK: Reading

    private func catchUp() {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        var outputs: [CodexRollout.Output] = []
        for url in rolloutFiles() {
            guard !isCancelled else { return }
            guard let modified = modificationDate(url), modified >= cutoff else { continue }
            outputs += openFile(url)
        }
        if !outputs.isEmpty { handler(Batch(outputs: outputs, isReplay: true)) }
    }

    private func changed(_ paths: [String]) {
        guard !isCancelled else { return }
        var outputs: [CodexRollout.Output] = []
        for path in Set(paths) where Self.isRollout(path) {
            if files[path] != nil {
                outputs += readNew(path)
            } else if let modified = modificationDate(URL(fileURLWithPath: path)),
                      modified >= Date().addingTimeInterval(-recentWindow) {
                // A session that started after us, or an old one that came back to life. Attribute changes on
                // old files fire events too: those stay ignored. Whatever was in the file before is history;
                // the monitor tells news apart by the lines' own timestamps.
                outputs += openFile(URL(fileURLWithPath: path))
            }
        }
        forgetQuietFiles()
        if !outputs.isEmpty { handler(Batch(outputs: outputs, isReplay: false)) }
    }

    private func openFile(_ url: URL) -> [CodexRollout.Output] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var tracked = Tracked(rollout: CodexRollout(fileName: url.lastPathComponent), offset: size, touched: Date())
        var outputs: [CodexRollout.Output] = []
        if size <= UInt64(Self.tailBytes) {
            try? handle.seek(toOffset: 0)
            outputs += consume((try? handle.read(upToCount: Int(size))) ?? Data(), into: &tracked)
        } else {
            // The first line names the session and its folder; the tail says what it is doing now.
            try? handle.seek(toOffset: 0)
            let head = (try? handle.read(upToCount: Self.headBytes)) ?? Data()
            if let newline = head.firstIndex(of: 0x0A) {
                outputs += tracked.rollout.read(String(decoding: head[..<newline], as: UTF8.self))
            }
            if !tracked.rollout.isSubagent {
                try? handle.seek(toOffset: size - UInt64(Self.tailBytes))
                outputs += consume(Self.fromFirstFullLine((try? handle.read(upToCount: Self.tailBytes)) ?? Data()),
                                   into: &tracked)
            }
        }
        // Subagent files are remembered too, so their appends are skipped instead of reopening them each time.
        files[url.path]?.source?.cancel()
        if !tracked.rollout.isSubagent { tracked.source = follow(url.path) }
        files[url.path] = tracked
        return tracked.rollout.isSubagent ? [] : outputs
    }

    private func readNew(_ path: String) -> [CodexRollout.Output] {
        guard var tracked = files[path], let handle = FileHandle(forReadingAtPath: path) else {
            letGo(path)
            return []
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        tracked.touched = Date()
        if size < tracked.offset {
            // Rewritten from scratch: start over.
            tracked.offset = 0
            tracked.pending.removeAll()
        }
        guard size > tracked.offset, !tracked.rollout.isSubagent else {
            tracked.offset = size
            files[path] = tracked
            return []
        }
        var data: Data
        if size - tracked.offset > UInt64(Self.tailBytes) {
            // Far behind (the Mac slept, a burst of output): only the latest part matters.
            try? handle.seek(toOffset: size - UInt64(Self.tailBytes))
            data = Self.fromFirstFullLine((try? handle.read(upToCount: Self.tailBytes)) ?? Data())
            tracked.pending.removeAll()
        } else {
            try? handle.seek(toOffset: tracked.offset)
            data = (try? handle.read(upToCount: Int(size - tracked.offset))) ?? Data()
        }
        tracked.offset = size
        let outputs = consume(data, into: &tracked)
        files[path] = tracked
        return outputs
    }

    /// A chunk read from the middle of a file starts inside a line: drop up to the first newline (all of it
    /// when there is none: one giant line).
    static func fromFirstFullLine(_ data: Data) -> Data {
        guard let newline = data.firstIndex(of: 0x0A) else { return Data() }
        return data[data.index(after: newline)...]
    }

    /// Splits into lines in one pass; an unfinished last line waits for the rest of it.
    private func consume(_ data: Data, into tracked: inout Tracked) -> [CodexRollout.Output] {
        tracked.pending.append(data)
        let buffer = tracked.pending
        var outputs: [CodexRollout.Output] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            if newline - start <= Self.maxLine {
                outputs += tracked.rollout.read(String(decoding: buffer[start..<newline], as: UTF8.self))
            }
            start = buffer.index(after: newline)
        }
        tracked.pending = buffer[start...].count > Self.maxLine ? Data() : Data(buffer[start...])
        return outputs
    }

    /// Files nobody wrote to for a long while, and the oldest beyond `maxFollowed`, are let go; if they come
    /// back to life FSEvents reports them and they are opened again.
    private func forgetQuietFiles() {
        let cutoff = Date().addingTimeInterval(-Self.forgetAfter)
        let byAge = files.sorted { $0.value.touched > $1.value.touched }
        for (index, (path, tracked)) in byAge.enumerated() where index >= Self.maxFollowed || tracked.touched < cutoff {
            letGo(path)
        }
    }

    private func letGo(_ path: String) {
        files[path]?.source?.cancel()
        files[path] = nil
    }

    /// kqueue watch: fires on every append even while the writer keeps the file open.
    private func follow(_ path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                               eventMask: [.extend, .write, .delete, .rename],
                                                               queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, !isCancelled else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                // Archived or removed: FSEvents reports it again if it shows up somewhere.
                letGo(path)
                return
            }
            let outputs = readNew(path)
            if !outputs.isEmpty { handler(Batch(outputs: outputs, isReplay: false)) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func rolloutFiles() -> [URL] {
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                    options: [.skipsHiddenFiles])
        var found: [URL] = []
        while let url = walker?.nextObject() as? URL {
            if Self.isRollout(url.path) { found.append(url) }
        }
        return found
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func isRollout(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("rollout-") && name.hasSuffix(".jsonl")
    }

    // MARK: FSEvents

    private func startStream() {
        // The stream retains the watcher for as long as it lives, so a callback already queued when `stop()`
        // tears the stream down still finds a live object (and then sees the cancelled flag).
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<CodexWatcher>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in
                guard let info else { return }
                Unmanaged<CodexWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<CodexWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.changed(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer)
        // FSEvents reports real paths (/private/var/…, resolved symlinks); watch the real one so they match.
        let watched = root.resolvingSymlinksInPath().path
        guard let stream = FSEventStreamCreate(nil, callback, &context, [watched] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }
}
