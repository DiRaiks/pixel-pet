import Foundation

/// The parts of `claude -p --output-format stream-json --include-partial-messages` the pet reads.
public enum ClaudeStream: Equatable, Sendable {
    case text(String)
    /// The model finished its answer; the CLI may keep running a little (turn summary) before `result`.
    case messageDone
    /// The session id from `system/init`, for `--resume` follow-ups.
    case session(String)
    case result(String)
    case failure(String)
    case limits(UsageLimits)

    public static func parse(_ line: String, at now: Date) -> ClaudeStream? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        switch json["type"] as? String {
        case "system":
            guard json["subtype"] as? String == "init", let id = json["session_id"] as? String, !id.isEmpty else { return nil }
            return .session(id)
        case "stream_event":
            if (json["event"] as? [String: Any])?["type"] as? String == "message_stop" { return .messageDone }
            guard let event = json["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .text(text)
        case "result":
            let text = json["result"] as? String ?? ""
            return (json["is_error"] as? Bool ?? false) ? .failure(text) : .result(text)
        case "rate_limit_event":
            return UsageLimits.fromStreamLine(line, observedAt: now).map(ClaudeStream.limits)
        default:
            return nil
        }
    }
}

/// Translation by Claude for when Apple's on-device translation is too literal.
public enum ClaudeTranslation {
    public enum Failure: Error, Equatable, Sendable {
        case claude(String)
        case cancelled
        case noOutput
    }

    /// The text itself goes on stdin, after this instruction.
    public static func instruction(target: String) -> String {
        let name = Locale(identifier: "en").localizedString(forLanguageCode: target) ?? target
        let language = name == target ? target : "\(name) (\(target))"
        return """
        Translate the text from standard input into \(language). Keep the meaning, tone, formatting and \
        technical terms (code, product names, identifiers stay as they are). Reply with only the translation, \
        no notes or quotes.
        """
    }
}
