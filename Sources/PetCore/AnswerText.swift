import Foundation

/// Splits a Claude answer into prose and fenced code blocks. The card renders prose as inline Markdown,
/// which would otherwise flatten a code block into one line with its language tag ("bash git reset…").
public enum AnswerText {
    public enum Segment: Equatable, Sendable {
        case prose(String)
        case code(String)
    }

    public static func segments(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var prose: [Substring] = []
        var code: [Substring]?
        var fence = ""

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { out.append(.prose(joined)) }
            prose = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if var block = code {
                if isClosing(trimmed, fence) {
                    out.append(.code(block.joined(separator: "\n")))
                    code = nil
                } else {
                    block.append(line)
                    code = block
                }
            } else if let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                flushProse()
                fence = marker
                code = []
            } else {
                prose.append(line)
            }
        }
        if let block = code {
            // Streaming: the closing fence hasn't arrived yet.
            out.append(.code(block.joined(separator: "\n").trimmingCharacters(in: .newlines)))
        }
        flushProse()
        return out
    }

    /// A closing fence is the opening marker's character repeated at least as many times, nothing else.
    private static func isClosing(_ line: Substring, _ fence: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        return body.hasPrefix(fence) && body.allSatisfy { $0 == fence.first }
    }
}
