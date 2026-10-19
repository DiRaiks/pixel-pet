import Foundation
import Testing
@testable import PetCore

@Suite struct TranslationPlanTests {
    @Test func nativeTextGoesToTheForeignLanguage() {
        let plan = TranslationPlan.make(text: "  Привет, мир  ", detected: "ru", native: "ru", foreign: "en")
        #expect(plan == TranslationPlan(text: "Привет, мир", source: "ru", target: "en"))
    }

    @Test func anythingElseGoesToNative() {
        #expect(TranslationPlan.make(text: "Hello", detected: "en", native: "ru", foreign: "en")?.target == "ru")
        #expect(TranslationPlan.make(text: "Hallo Welt", detected: "de", native: "ru", foreign: "en")
            == TranslationPlan(text: "Hallo Welt", source: "de", target: "ru"))
    }

    @Test func undetectedLanguageLetsTheSystemGuess() {
        #expect(TranslationPlan.make(text: "ok", detected: nil, native: "ru", foreign: "en")
            == TranslationPlan(text: "ok", source: nil, target: "ru"))
        #expect(TranslationPlan.make(text: "ok", detected: "und", native: "ru", foreign: "en")?.source == nil)
    }

    @Test func emptySelectionHasNoPlan() {
        #expect(TranslationPlan.make(text: " \n\t ", detected: "en", native: "ru", foreign: "en") == nil)
    }

    @Test func veryLongSelectionsAreCut() {
        let long = String(repeating: "a", count: TranslationPlan.maxLength + 50)
        #expect(TranslationPlan.make(text: long, detected: "en", native: "ru", foreign: "en")?.text.count == TranslationPlan.maxLength)
    }

    @Test func regionalCodesCompareByLanguage() {
        #expect(TranslationPlan.make(text: "Привет", detected: "ru-RU", native: "ru", foreign: "en")?.target == "en")
    }

    @Test func configDefaultsAndRoundTrip() throws {
        let old = try JSONDecoder().decode(PetConfig.self, from: Data(#"{"scale":4}"#.utf8))
        #expect(old.nativeLanguage == "ru")
        #expect(old.foreignLanguage == "en")
        #expect(old.askModel == "haiku")
        var c = PetConfig()
        c.nativeLanguage = "uk"
        #expect(try JSONDecoder().decode(PetConfig.self, from: JSONEncoder().encode(c)).nativeLanguage == "uk")
    }
}

@Suite struct SelectionDecisionTests {
    func decide(_ ax: SelectionDecision.Accessibility, frontmostIsSelf: Bool = false, secureInput: Bool = false,
                clipboardLossy: Bool = false) -> SelectionDecision {
        SelectionDecision.make(accessibility: ax, frontmostIsSelf: frontmostIsSelf, secureInput: secureInput,
                               clipboardLossy: clipboardLossy)
    }

    @Test func accessibilityTextIsUsedDirectly() {
        #expect(decide(.text("hello")) == .use("hello"))
    }

    @Test func emptySelectionNeverFallsBackToCopy() {
        // In IDEs ⌘C with nothing selected copies the whole line; an empty AX answer means "nothing selected".
        #expect(decide(.text("   ")) == .stop(.nothingSelected))
    }

    @Test func unavailableAccessibilityFallsBackToCopy() {
        #expect(decide(.unavailable) == .copy)
    }

    @Test func passwordFieldsAreNeverRead() {
        #expect(decide(.secureField) == .stop(.secureField))
        #expect(decide(.text("hunter2"), secureInput: true) == .stop(.secureField))
        #expect(decide(.unavailable, secureInput: true) == .stop(.secureField))
    }

    @Test func noCopyIntoOurselvesOrOverAClipboardWeCantRestore() {
        #expect(decide(.unavailable, frontmostIsSelf: true) == .stop(.nothingSelected))
        #expect(decide(.unavailable, clipboardLossy: true) == .stop(.clipboardBusy))
    }
}

@Suite struct TranslationPlanEdgeTests {
    @Test func sameNativeAndForeignMeansNothingToDo() {
        #expect(TranslationPlan.make(text: "Привет", detected: "ru", native: "ru", foreign: "ru") == nil)
    }

    @Test func scriptAndRegionSubtagsCompareByLanguage() {
        #expect(TranslationPlan.make(text: "你好", detected: "zh-Hans", native: "zh", foreign: "en")?.target == "en")
        #expect(TranslationPlan.make(text: "x", detected: "und-US", native: "ru", foreign: "en")?.source == nil)
    }

    @Test func truncationCountsCharactersNotBytes() {
        let emoji = String(repeating: "👩‍💻", count: TranslationPlan.maxLength + 1)
        #expect(TranslationPlan.make(text: emoji, detected: "en", native: "ru", foreign: "en")?.text.count == TranslationPlan.maxLength)
    }
}
