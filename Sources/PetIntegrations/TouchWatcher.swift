import Foundation
import PetCore

/// Follows the system log for a hardware key waiting for a touch (see `TouchWait`), with one long-running
/// `log stream` filtered down to that single message: no CPU to speak of, nothing else read. `handler` gets
/// the time of each signal, on a private queue.
///
/// The stream runs under a tiny `sh` watchdog that ends it when the app is gone, so a crash or force quit
/// doesn't leave `log stream` running. If the stream ends on its own it is restarted, waiting longer each
/// time it dies young (up to `maxRestartDelay`).
public final class TouchWatcher: @unchecked Sendable {
    public static let maxRestartDelay: TimeInterval = 5 * 60
    /// A stream that lived this long counts as healthy: the next restart waits the base delay again.
    static let healthyRun: TimeInterval = 30

    /// `log stream` under a watchdog: $1 is the app's pid, the rest go to `log`.
    static let watchdog = """
    app=$1; shift
    /usr/bin/log "$@" & stream=$!
    trap 'kill $stream 2>/dev/null; exit 0' TERM INT
    while kill -0 "$app" 2>/dev/null && kill -0 "$stream" 2>/dev/null; do sleep 5 & wait $!; done
    kill $stream 2>/dev/null
    """

    public static var defaultLaunch: (URL, [String]) {
        let log = ["stream", "--level", "debug", "--style", "ndjson", "--predicate", TouchWait.predicate]
        return (URL(fileURLWithPath: "/bin/sh"),
                ["-c", watchdog, "pixelpet-touch", String(ProcessInfo.processInfo.processIdentifier)] + log)
    }

    private let executable: URL
    private let arguments: [String]
    private let restartDelay: TimeInterval
    private let handler: @Sendable (Date) -> Void
    private let queue = DispatchQueue(label: "dev.pixelpet.touch")
    // Touched only on `queue`.
    private var process: Process?
    private var reader: FileHandle?
    private var generation = 0
    private var pending = Data()
    private var stopped = true
    private var nextDelay: TimeInterval
    private var startedAt = Date()

    public init(executable: URL? = nil, arguments: [String]? = nil, restartDelay: TimeInterval = 10,
                handler: @escaping @Sendable (Date) -> Void) {
        let launch = Self.defaultLaunch
        self.executable = executable ?? launch.0
        self.arguments = arguments ?? launch.1
        self.restartDelay = restartDelay
        nextDelay = restartDelay
        self.handler = handler
    }

    public func start() {
        queue.async { [self] in
            guard stopped else { return }
            stopped = false
            nextDelay = restartDelay
            launch()
        }
    }

    public func stop() {
        queue.sync {
            stopped = true
            generation += 1
            reader?.readabilityHandler = nil
            reader = nil
            if let process, process.isRunning { process.terminate() }
            process = nil
            pending.removeAll()
        }
    }

    private func launch() {
        guard !stopped, process == nil else { return }
        generation += 1
        let current = generation
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            queue.async { self.ended(current) }
        }
        do {
            try process.run()
        } catch {
            NSLog("PixelPet: touch watcher could not start: \(error.localizedDescription)")
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            scheduleRestart()
            return
        }
        self.process = process
        startedAt = Date()
        let reader = output.fileHandleForReading
        self.reader = reader
        reader.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            queue.async { self.consume(chunk, generation: current) }
        }
    }

    private func ended(_ which: Int) {
        guard which == generation, !stopped else { return }
        reader?.readabilityHandler = nil
        reader = nil
        process = nil
        pending.removeAll()
        // Healthy streams restart after the base delay; ones that keep dying young wait longer and longer.
        if Date().timeIntervalSince(startedAt) >= Self.healthyRun { nextDelay = restartDelay }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !stopped else { return }
        let delay = nextDelay
        nextDelay = min(nextDelay * 2, Self.maxRestartDelay)
        let current = generation
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, current == generation else { return }
            launch()
        }
    }

    private func consume(_ chunk: Data, generation which: Int) {
        guard !stopped, which == generation else { return }
        pending.append(chunk)
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            let line = String(decoding: pending[start..<newline], as: UTF8.self)
            if TouchWait.isTouchRequest(line) { handler(Date()) }
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
        // Nothing we look for is long; don't let an odd stream grow the buffer.
        if pending.count > 1 << 20 { pending.removeAll() }
    }
}
