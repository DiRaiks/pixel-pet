import Foundation

/// Reads the lines appended to a file from now on, twice a second, until stopped.
@MainActor
final class TranscriptTail {
    private var offset: UInt64
    private var partial = Data()
    private var timer: Timer?

    init?(path: String, onLine: @escaping @MainActor (Data) -> Void) {
        guard let handle = FileHandle(forReadingAtPath: path), let end = try? handle.seekToEnd() else { return nil }
        try? handle.close()
        offset = end
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for line in self.read(path) {
                    guard self.timer != nil else { return }
                    onLine(line)
                }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Complete lines since the last read; an unfinished last line waits for the next read. At most 4 MB a
    /// read, and a line longer than 16 MB is dropped.
    private func read(_ path: String) -> [Data] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
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
