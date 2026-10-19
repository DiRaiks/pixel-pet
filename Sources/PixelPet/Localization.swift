import Observation

/// The interface language: English by default, Russian if chosen in settings. It's the app's own setting,
/// independent of the system language.
enum UILanguage: String, CaseIterable, Sendable {
    case en, ru

    /// Each language is listed under its own name.
    var title: String {
        switch self {
        case .en: "English"
        case .ru: "Русский"
        }
    }
}

/// Observable so SwiftUI views that read a string redraw when the language changes; AppKit menus and
/// windows pick it up the next time they are built or opened.
@MainActor
@Observable
final class Loc {
    static let shared = Loc()
    var language = UILanguage.en
}

/// A UI string, written as its English and Russian text side by side at the call site.
@MainActor
func L(_ en: String, _ ru: String) -> String {
    Loc.shared.language == .ru ? ru : en
}
