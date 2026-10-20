import Foundation
import PetCore

/// One streamed `claude -p` turn: the input goes over stdin (never in the process list), events come back
/// as they arrive. `.done` fires at `message_stop`, before the CLI finishes its turn summary and exits.
public enum ClaudeChat {
    public enum Event: Sendable {
        case session(String)
        /// The whole answer so far.
        case text(String)
        case done(String)
        case limits(UsageLimits)
    }

    public static func run(claude: URL, arguments: [String], input: String, timeout: TimeInterval = 180,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           onEvent: @escaping @Sendable (Event) -> Void) async -> Result<String, ClaudeTranslation.Failure> {
        await run(claude: claude, arguments: arguments, stdin: Data(input.utf8), timeout: timeout, environment: environment,
                  onEvent: onEvent)
    }

    /// The same with raw stdin, e.g. a `--input-format stream-json` message carrying images.
    public static func run(claude: URL, arguments: [String], stdin: Data, timeout: TimeInterval = 180,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           onEvent: @escaping @Sendable (Event) -> Void) async -> Result<String, ClaudeTranslation.Failure> {
        let state = ChatState()
        let started = await ClaudeProcess.run(
            claude: claude, arguments: arguments, stdin: stdin,
            timeout: timeout, killAfter: 3, environment: environment
        ) { line in
            switch ClaudeStream.parse(line, at: Date()) {
            case .session(let id): onEvent(.session(id))
            case .text(let delta): onEvent(.text(state.append(delta)))
            case .messageDone: if let text = state.markDone(fallback: nil) { onEvent(.done(text)) }
            case .result(let final):
                state.finish(.success(final))
                // Without streamed deltas (short or cached answers) the result is the only copy of the text.
                if let text = state.markDone(fallback: final) { onEvent(.done(text)) }
            case .failure(let message): state.finish(.failure(.claude(message)))
            case .limits(let limits): onEvent(.limits(limits))
            case nil: break
            }
        }
        if Task.isCancelled { return .failure(.cancelled) }
        guard started else { return .failure(.noOutput) }
        return state.outcome
    }
}

private final class ChatState: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var doneSent = false
    private var final: Result<String, ClaudeTranslation.Failure>?

    func append(_ delta: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        text += delta
        return text
    }

    /// The streamed text (or the fallback when nothing streamed) the first time it's called, then nil.
    /// With no text and no fallback it waits, so the final result can still provide one.
    func markDone(fallback: String?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !doneSent else { return nil }
        let answer = text.isEmpty ? (fallback ?? "") : text
        guard !answer.isEmpty || fallback != nil else { return nil }
        doneSent = true
        return answer
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

/// Quick questions from the pet's ask card; the session is kept so follow-ups can `--resume` it.
public enum ClaudeAsk {
    static let systemPrompt = """
    The user is asking a quick question from a small popup on their Mac desktop. Answer concisely and \
    directly, in the user's language. Prefer short paragraphs or brief lists.
    """

    /// `streamInput` when the question carries images: the message comes as one stream-json line.
    public static func arguments(model: String, resume: String?, streamInput: Bool = false) -> [String] {
        var args = [
            "-p",
            "--model", model,
            "--tools", "",
            "--setting-sources", "project",
            "--append-system-prompt", systemPrompt,
            "--output-format", "stream-json", "--verbose", "--include-partial-messages",
        ]
        if streamInput { args += ["--input-format", "stream-json"] }
        if let resume { args += ["--resume", resume] }
        return args
    }
}
