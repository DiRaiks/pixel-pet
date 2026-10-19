import Foundation
import PetCore

/// Asks Claude Code for the current subscription limits with the cheapest possible request:
/// a one-word haiku reply with no tools. The answer is ignored; the `rate_limit_event` line is what we want.
public enum LimitsProbe {
    public static let arguments = [
        "-p", "Reply with one word: ok",
        "--model", "haiku",
        "--tools", "",
        "--setting-sources", "project",
        "--no-session-persistence",
        "--output-format", "stream-json", "--verbose",
    ]

    public static func run(claude: URL, timeout: TimeInterval = 60, killAfter: TimeInterval = 3,
                           environment: [String: String] = ProcessInfo.processInfo.environment) async -> UsageLimits? {
        let found = Found()
        let started = await ClaudeProcess.run(claude: claude, arguments: arguments, stdin: nil, timeout: timeout,
                                              killAfter: killAfter, environment: environment) { line in
            if let limits = UsageLimits.fromStreamLine(line, observedAt: Date()) { found.merge(limits) }
        }
        return started ? found.value : nil
    }
}

private final class Found: @unchecked Sendable {
    private let lock = NSLock()
    private var limits: UsageLimits?
    func merge(_ next: UsageLimits) {
        lock.lock()
        limits = limits.map { $0.merged(with: next) } ?? next
        lock.unlock()
    }
    var value: UsageLimits? {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }
}
