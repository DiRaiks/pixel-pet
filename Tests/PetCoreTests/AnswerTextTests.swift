import Testing
@testable import PetCore

@Suite struct AnswerTextTests {
    @Test func plainTextIsOneProseSegment() {
        #expect(AnswerText.segments("Just **text**.\nTwo lines.") == [.prose("Just **text**.\nTwo lines.")])
    }

    @Test func fencedBlockBecomesCodeWithoutItsLanguageTag() {
        let answer = "Run this:\n\n```bash\ngit reset --soft HEAD~1\n```\n\nThen commit again."
        #expect(AnswerText.segments(answer) == [
            .prose("Run this:"), .code("git reset --soft HEAD~1"), .prose("Then commit again."),
        ])
    }

    @Test func blockKeepsInnerLinesAndIndentation() {
        let answer = "```swift\nif x {\n    y()\n}\n```"
        #expect(AnswerText.segments(answer) == [.code("if x {\n    y()\n}")])
    }

    /// While streaming the closing fence hasn't arrived yet: the rest is already shown as code.
    @Test func unterminatedFenceIsCodeSoFar() {
        #expect(AnswerText.segments("Try:\n```\nls -la\nfoo") == [.prose("Try:"), .code("ls -la\nfoo")])
    }

    @Test func tildeFencesAndIndentedFencesCount() {
        #expect(AnswerText.segments("~~~\na\n~~~") == [.code("a")])
        #expect(AnswerText.segments("  ```py\nb\n  ```") == [.code("b")])
    }

    @Test func inlineBackticksStayProse() {
        #expect(AnswerText.segments("Use `git reset HEAD~1` instead.") == [.prose("Use `git reset HEAD~1` instead.")])
    }

    @Test func emptyAnswerHasNoSegments() {
        #expect(AnswerText.segments("").isEmpty)
        #expect(AnswerText.segments("```\n```") == [.code("")])
    }
}
