import Foundation
import PetCore

/// Reads Codex's subscription limits from a short-lived `codex app-server`: the JSON-RPC handshake and one
/// `account/rateLimits/read` request. No model call, so it costs nothing against the limits it reads.
public enum CodexLimitsProbe {
    static let requestID = 2
    static let messages: Data = {
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"pixelpet","title":"Pixel Pet","version":"0.1"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}"#,
        ]
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }()

    public static func run(codex: URL, timeout: TimeInterval = 20, killAfter: TimeInterval = 2,
                           environment: [String: String] = ProcessInfo.processInfo.environment) async -> UsageLimits? {
        let found = FoundLimits()
        // The server quits as soon as its input closes, so the input stays open until the answer arrives.
        let started = await ClaudeProcess.run(claude: codex, arguments: ["app-server"], stdin: messages, timeout: timeout,
                                              killAfter: killAfter, environment: environment,
                                              until: { line in
                                                  guard let limits = CodexRollout.appServerLimits(line, id: requestID, observedAt: Date())
                                                  else { return CodexRollout.isResponse(line, id: requestID) }
                                                  found.set(limits)
                                                  return true
                                              }) { _ in }
        return started ? found.value : nil
    }
}

private final class FoundLimits: @unchecked Sendable {
    private let lock = NSLock()
    private var limits: UsageLimits?
    func set(_ value: UsageLimits) {
        lock.lock()
        limits = value
        lock.unlock()
    }
    var value: UsageLimits? {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }
}
