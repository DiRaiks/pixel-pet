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

    /// Streams the translation: `onText` gets the text so far after every delta, `onDone` the full text
    /// as soon as the model stops. The source text goes over stdin. Cancelling the task stops the CLI.
    public static func run(claude: URL, text: String, target: String, model: String = "sonnet",
                           timeout: TimeInterval = 120,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           onText: @escaping @Sendable (String) -> Void,
                           onDone: @escaping @Sendable (String) -> Void = { _ in },
                           onLimits: @escaping @Sendable (UsageLimits) -> Void) async -> Result<String, Failure> {
        await ClaudeChat.run(claude: claude, arguments: arguments(target: target, model: model), input: text,
                             timeout: timeout, environment: environment) { event in
            switch event {
            case .text(let partial): onText(partial)
            case .done(let full): onDone(full)
            case .limits(let limits): onLimits(limits)
            case .session: break
            }
        }
    }
}
