import Foundation
import PetCore

extension ClaudeTranslation {
    public static func arguments(target: String, model: String) -> [String] {
        [
            "-p", instruction(target: target),
            "--model", model,
            "--tools", "",
            "--setting-sources", "project",
            "--no-session-persistence",
            "--output-format", "stream-json", "--verbose", "--include-partial-messages",
        ]
    }

    /// Streams the translation: `onText` gets the text so far after every delta. The source text goes
    /// over stdin so it never shows up in the process list. Cancelling the task stops the CLI.
    public static func run(claude: URL, text: String, target: String, model: String = "sonnet",
                           timeout: TimeInterval = 120,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           onText: @escaping @Sendable (String) -> Void,
                           onLimits: @escaping @Sendable (UsageLimits) -> Void) async -> Result<String, Failure> {
        let state = StreamState()
        let started = await ClaudeProcess.run(
            claude: claude, arguments: arguments(target: target, model: model), stdin: Data(text.utf8),
            timeout: timeout, killAfter: 3, environment: environment
        ) { line in
            switch ClaudeStream.parse(line, at: Date()) {
            case .text(let delta): onText(state.append(delta))
            case .result(let final): state.finish(.success(final))
            case .failure(let message): state.finish(.failure(.claude(message)))
            case .limits(let limits): onLimits(limits)
            case nil: break
            }
        }
        if Task.isCancelled { return .failure(.cancelled) }
        guard started else { return .failure(.noOutput) }
        return state.outcome
    }
}

private final class StreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var final: Result<String, ClaudeTranslation.Failure>?

    func append(_ delta: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        text += delta
        return text
    }

    func finish(_ result: Result<String, ClaudeTranslation.Failure>) {
        lock.lock()
        final = result
        lock.unlock()
    }

    var outcome: Result<String, ClaudeTranslation.Failure> {
        lock.lock()
        defer { lock.unlock() }
        if let final { return final }
        return text.isEmpty ? .failure(.noOutput) : .success(text)
    }
}
