import Darwin
import Foundation

/// Runs the Claude Code CLI for the pet's own small jobs: no user settings or hooks, no API credentials
/// from the environment (they would bill an API account instead of the subscription), marked internal so
/// the pet's hook ignores it. Output is read line by line without blocking; cancelling the task, or the
/// timeout, sends SIGTERM and then SIGKILL.
enum ClaudeProcess {
    static let strippedEnvironment = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
    ]
    static let maxOutput = 4 << 20

    /// Returns false if the process couldn't be started. With `until`, the input stays open after `stdin` is
    /// written (for servers that quit on end of input) and the process is stopped once `until` accepts a line.
    static func run(claude: URL, arguments: [String], stdin: Data?, timeout: TimeInterval, killAfter: TimeInterval,
                    environment: [String: String], until: (@Sendable (String) -> Bool)? = nil,
                    onLine: @escaping @Sendable (String) -> Void) async -> Bool {
        let process = Process()
        process.executableURL = claude
        process.arguments = arguments
        var env = environment
        for key in strippedEnvironment { env.removeValue(forKey: key) }
        env["PIXELPET_INTERNAL"] = "1"
        process.environment = env
        let workdir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workdir
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input

        let box = ProcessBox(process)
        let lines = LineSplitter(limit: maxOutput) { line in
            onLine(line)
            if let until, until(line) { box.stop(killAfter: killAfter) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { lines.append(chunk) }
        }
        let started: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    Running.shared.remove(box)
                    continuation.resume(returning: true)
                }
                do {
                    try process.run()
                    Running.shared.add(box)
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                if let stdin {
                    let writer = input.fileHandleForWriting
                    // A claude that exits before reading it all must not take the app down with SIGPIPE:
                    // the write then just fails.
                    _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                    DispatchQueue.global().async {
                        try? writer.write(contentsOf: stdin)
                        // Closed when the process ends (the pipe goes with it) rather than right away.
                        if until == nil { try? writer.close() }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { box.stop(killAfter: killAfter) }
            }
        } onCancel: {
            box.stop(killAfter: killAfter)
        }
        guard started else { return false }
        // Let the last buffered chunk arrive, then stop listening.
        try? await Task.sleep(for: .milliseconds(150))
        output.fileHandleForReading.readabilityHandler = nil
        lines.flush()
        return true
    }
}

/// Splits streamed bytes into lines, with a cap on the total size.
private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var total = 0
    private let limit: Int
    private let onLine: @Sendable (String) -> Void

    init(limit: Int, onLine: @escaping @Sendable (String) -> Void) {
        self.limit = limit
        self.onLine = onLine
    }

    func append(_ chunk: Data) {
        lock.lock()
        guard total < limit else { lock.unlock(); return }
        total += chunk.count
        pending.append(chunk)
        var complete: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            complete.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        lock.unlock()
        complete.forEach(onLine)
    }

    func flush() {
        lock.lock()
        let rest = pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        lock.unlock()
        rest.map(onLine)
    }
}

/// Process isn't Sendable; only isRunning / terminate / pid are used across threads, which are thread-safe.
final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }

    func stop(killAfter: TimeInterval) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + killAfter) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

/// The CLI processes the pet has running, so quitting the app doesn't leave them behind (they'd otherwise run
/// on until their own API timeout, up to many minutes).
public enum ClaudeProcesses {
    /// SIGTERM to every one still running; called as the app quits.
    public static func terminateAll() {
        Running.shared.terminateAll()
    }
}

final class Running: @unchecked Sendable {
    static let shared = Running()
    private let lock = NSLock()
    private var boxes: [ObjectIdentifier: ProcessBox] = [:]

    func add(_ box: ProcessBox) {
        lock.lock()
        boxes[ObjectIdentifier(box)] = box
        lock.unlock()
    }

    func remove(_ box: ProcessBox) {
        lock.lock()
        boxes[ObjectIdentifier(box)] = nil
        lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let all = Array(boxes.values)
        lock.unlock()
        for box in all where box.process.isRunning { box.process.terminate() }
    }
}
