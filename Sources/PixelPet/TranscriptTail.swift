import Foundation

/// Reads the lines appended to a file from now on, twice a second, until stopped. The file is read on a
/// queue of its own; the lines are handed over on the main thread.
final class TranscriptTail: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "pixelpet.transcript-tail", qos: .utility)
    private let timer: DispatchSourceTimer
    private let onLine: @MainActor (Data) -> Void
    // Touched only on `queue`.
    private var offset: UInt64
    private var partial = Data()
    // Read on the main thread before each line goes out.
    private let lock = NSLock()
    private var stopped = false

    @MainActor
    init?(path: String, onLine: @escaping @MainActor (Data) -> Void) {
        guard let handle = FileHandle(forReadingAtPath: path), let end = try? handle.seekToEnd() else { return nil }
        try? handle.close()
        self.path = path
        self.onLine = onLine
        offset = end
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(200))
        // Not main-actor isolated, though written in a main-actor init: it runs on `queue`.
        timer.setEventHandler { @Sendable [weak self] in self?.poll() }
        timer.resume()
    }

    deinit { timer.cancel() }

    @MainActor
    func stop() {
        lock.withLock { stopped = true }
        timer.cancel()
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func poll() {
        let lines = read()
        guard !lines.isEmpty else { return }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                for line in lines {
                    guard !isStopped else { return }
                    onLine(line)
                }
            }
        }
    }

    /// Complete lines since the last read; an unfinished last line waits for the next read. At most 4 MB a
    /// read, and a line longer than 16 MB is dropped.
    private func read() -> [Data] {
        guard !isStopped, let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty else { return [] }
        offset += UInt64(chunk.count)
        partial.append(chunk)
        var lines = partial.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).map { Data($0) }
        if partial.last != UInt8(ascii: "\n"), let last = lines.popLast() { partial = last } else { partial = Data() }
        if partial.count > 16 << 20 { partial = Data() }
        return lines
    }
}

extension TranscriptTail {
    /// The complete lines in the last `bytes` of a file (the first, likely cut, is dropped), oldest first.
    static func lastLines(_ path: String, bytes: Int = 64 << 10) -> [Data] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return [] }
        let start = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).map { Data($0) }
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    static func size(_ path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
    }
}
