import Darwin
import Foundation
import PetCore

/// Asks Claude Code for the current subscription limits with the cheapest possible request:
/// a one-word haiku reply, no tools, no user settings or hooks, not saved as a session.
/// The answer is ignored; the `rate_limit_event` line in the stream is what we want.
public enum LimitsProbe {
    public static let arguments = [
        "-p", "Reply with one word: ok",
        "--model", "haiku",
        "--tools", "",
        "--setting-sources", "project",
        "--no-session-persistence",
        "--output-format", "stream-json", "--verbose",
    ]

    /// Credentials that would bill an API account instead of the subscription (and report no limits).
    static let strippedEnvironment = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
    ]
    static let maxOutput = 4 << 20

    public static func run(claude: URL, timeout: TimeInterval = 60, killAfter: TimeInterval = 3,
                           environment: [String: String] = ProcessInfo.processInfo.environment) async -> UsageLimits? {
        let process = Process()
        process.executableURL = claude
        process.arguments = arguments
        var env = environment
        for key in strippedEnvironment { env.removeValue(forKey: key) }
        env["PIXELPET_INTERNAL"] = "1"
        process.environment = env
        let workdir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workdir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        // Non-blocking collection: a grandchild holding the pipe open can't stall us after the process is gone.
        let output = Collector(limit: maxOutput)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { output.append(chunk) }
        }
        let box = ProcessBox(process)
        let started: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
                return
            }
            // SIGTERM at the deadline, SIGKILL if it's ignored.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard box.process.isRunning else { return }
                box.process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + killAfter) {
                    if box.process.isRunning { kill(box.process.processIdentifier, SIGKILL) }
                }
            }
        }
        guard started else { return nil }
        // Let the last buffered chunk arrive, then stop listening.
        try? await Task.sleep(for: .milliseconds(150))
        pipe.fileHandleForReading.readabilityHandler = nil

        let now = Date()
        return String(decoding: output.data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { UsageLimits.fromStreamLine(String($0), observedAt: now) }
            .reduce(nil) { acc, next in acc.map { $0.merged(with: next) } ?? next }
    }
}

/// Thread-safe byte sink with a size cap.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard buffer.count < limit else { return }
        buffer.append(chunk.prefix(limit - buffer.count))
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// Process isn't Sendable; it is only used here for isRunning / terminate / pid, which are thread-safe.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}
