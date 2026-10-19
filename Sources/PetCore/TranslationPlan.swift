import Foundation

/// What to translate and in which direction: your own language goes to the foreign one, everything else
/// comes into yours. Language codes are BCP-47 ("ru", "en", "ru-RU"); only the language part is compared.
public struct TranslationPlan: Equatable, Sendable {
    public static let maxLength = 10_000

    public var text: String
    /// nil lets the translation framework detect the language itself.
    public var source: String?
    public var target: String

    public init(text: String, source: String?, target: String) {
        self.text = text
        self.source = source
        self.target = target
    }

    public static func make(text: String, detected: String?, native: String, foreign: String) -> TranslationPlan? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, language(native) != language(foreign) else { return nil }
        let source = detected.flatMap { $0.isEmpty || language($0) == "und" ? nil : $0 }
        let isNative = source.map { language($0) == language(native) } ?? false
        return TranslationPlan(text: String(trimmed.prefix(maxLength)), source: source, target: isNative ? foreign : native)
    }

    static func language(_ code: String) -> Substring {
        code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(code)
    }
}

/// Where the selected text may come from. Pure, so the privacy rules are pinned by tests:
/// password fields are never read, an empty selection never triggers ⌘C (IDEs copy the whole line then),
/// and ⌘C is never sent to ourselves or over a clipboard we couldn't restore exactly.
public enum SelectionDecision: Equatable, Sendable {
    public enum Accessibility: Equatable, Sendable {
        /// The focused element reported its selection (possibly empty).
        case text(String)
        /// The focused element is a password field.
        case secureField
        /// No answer: the app doesn't expose its selection through Accessibility.
        case unavailable
    }

    public enum Reason: Equatable, Sendable { case nothingSelected, secureField, clipboardBusy }

    case use(String)
    case copy
    case stop(Reason)

    public static func make(accessibility: Accessibility, frontmostIsSelf: Bool, secureInput: Bool,
                            clipboardLossy: Bool) -> SelectionDecision {
        if secureInput { return .stop(.secureField) }
        switch accessibility {
        case .secureField:
            return .stop(.secureField)
        case .text(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .stop(.nothingSelected) : .use(text)
        case .unavailable:
            if frontmostIsSelf { return .stop(.nothingSelected) }
            if clipboardLossy { return .stop(.clipboardBusy) }
            return .copy
        }
    }
}
