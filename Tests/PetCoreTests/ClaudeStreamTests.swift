import Foundation
import Testing
@testable import PetCore

@Suite struct ClaudeStreamTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func textDeltas() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Привет"}}}"#
        #expect(ClaudeStream.parse(line, at: now) == .text("Привет"))
    }

    @Test func finalResultAndErrors() {
        #expect(ClaudeStream.parse(#"{"type":"result","subtype":"success","is_error":false,"result":"Готово"}"#, at: now)
            == .result("Готово"))
        #expect(ClaudeStream.parse(#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#, at: now)
            == .failure("boom"))
    }

    @Test func limitsRideAlong() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.3,"resetsAt":1792416600}}}}"#
        guard case let .limits(limits) = ClaudeStream.parse(line, at: now) else {
            Issue.record("expected limits"); return
        }
        #expect(limits.fiveHour?.usedPercent == 30)
    }

    @Test func everythingElseIsIgnored() {
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"init"}"#, at: now) == nil)
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta"}}}"#, at: now) == nil)
        #expect(ClaudeStream.parse("not json", at: now) == nil)
    }

    @Test func translationInstructionNamesTheTargetLanguage() {
        let ru = ClaudeTranslation.instruction(target: "ru")
        #expect(ru.contains("Russian"))
        #expect(ru.contains("only the translation"))
        #expect(ClaudeTranslation.instruction(target: "en").contains("English"))
        #expect(ClaudeTranslation.instruction(target: "xx-unknown").contains("xx-unknown"))
    }
}

@Suite struct ClaudeStreamTurnTests {
    let now = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func messageStopMeansTheAnswerIsComplete() {
        #expect(ClaudeStream.parse(#"{"type":"stream_event","event":{"type":"message_stop"}}"#, at: now) == .messageDone)
    }

    @Test func initCarriesTheSessionForFollowUps() {
        #expect(ClaudeStream.parse(#"{"type":"system","subtype":"init","session_id":"abc-123","model":"claude-haiku-5-5"}"#, at: now)
            == .session("abc-123"))
    }
}

@Suite struct AskConversationTests {
    @Test func firstQuestionStreamsAndCompletes() {
        var c = AskConversation()
        #expect(c.canAsk)
        let asked = c.ask("Что такое stETH?")
        #expect(asked)
        #expect(!c.canAsk)
        c.receive(session: "s1")
        c.receive(text: "Это")
        c.receive(text: "Это токен")
        c.complete()
        #expect(c.turns == [AskConversation.Turn(question: "Что такое stETH?", answer: "Это токен", state: .done)])
        #expect(c.sessionID == "s1")
        #expect(c.canAsk)
        #expect(c.lastAnswer == "Это токен")
    }

    @Test func blankQuestionsAreIgnored() {
        var c = AskConversation()
        let asked = c.ask("   \n")
        #expect(!asked)
        #expect(c.turns.isEmpty)
    }

    @Test func followUpReusesTheSession() {
        var c = AskConversation()
        c.ask("a")
        c.receive(session: "s1")
        c.complete()
        #expect(c.resumeID == nil)
        c.ask("b")
        #expect(c.resumeID == "s1")
        #expect(c.turns.count == 2)
    }

    @Test func noFollowUpWithoutASession() {
        var c = AskConversation()
        c.ask("a")
        c.complete()
        c.ask("b")
        #expect(c.resumeID == nil)
    }

    @Test func failureAndCancelKeepTheConversationUsable() {
        var c = AskConversation()
        c.ask("a")
        c.fail("Not logged in")
        #expect(c.turns.last?.state == .failed("Not logged in"))
        #expect(c.canAsk)
        c.ask("b")
        c.receive(text: "partial")
        c.cancel()
        #expect(c.turns.last?.state == .stopped)
        #expect(c.turns.last?.answer == "partial")
        #expect(c.canAsk)
    }

    @Test func lateTextAfterCompletionIsIgnored() {
        var c = AskConversation()
        c.ask("a")
        c.receive(text: "done")
        c.complete()
        c.receive(text: "done and more")
        #expect(c.lastAnswer == "done")
    }

    @Test func resetStartsOver() {
        var c = AskConversation()
        c.ask("a")
        c.receive(session: "s")
        c.complete()
        c.reset()
        #expect(c.turns.isEmpty)
        #expect(c.sessionID == nil)
    }
}

@Suite struct AskTurnBindingTests {
    @Test func lateEventsFromAnEarlierTurnDontLeakIntoTheNextOne() {
        var c = AskConversation()
        c.ask("столица?")
        let first = c.currentTurn!
        c.receive(text: "Париж", turn: first)
        c.complete(turn: first)
        c.ask("река?")
        let second = c.currentTurn!
        // The first CLI process reports its final result after the follow-up started.
        c.receive(text: "Париж", turn: first)
        c.complete(turn: first)
        #expect(c.turns[second].state == .streaming)
        c.receive(text: "Сена", turn: second)
        c.complete(turn: second)
        #expect(c.turns.map(\.answer) == ["Париж", "Сена"])
    }
}

@Suite struct AskEpochTests {
    @Test func newConversationIgnoresEverythingFromTheOldRun() {
        var c = AskConversation()
        c.ask("старый вопрос")
        let old = c.ticket!
        c.reset()
        c.ask("новый вопрос")
        let fresh = c.ticket!
        // The old CLI process reports late: session, text, completion, cancellation.
        c.receive(session: "old-session", ticket: old)
        c.receive(text: "старый ответ", ticket: old)
        c.complete(ticket: old)
        c.cancel(ticket: old)
        #expect(c.sessionID == nil)
        #expect(c.turns[fresh.turn].state == .streaming)
        #expect(c.turns[fresh.turn].answer == "")
        c.receive(session: "new-session", ticket: fresh)
        c.receive(text: "новый ответ", ticket: fresh)
        c.complete(ticket: fresh)
        #expect(c.sessionID == "new-session")
        #expect(c.lastAnswer == "новый ответ")
    }

    @Test func lostSessionIsForgotten() {
        var c = AskConversation()
        c.ask("a")
        let t = c.ticket!
        c.receive(session: "s1", ticket: t)
        c.complete(ticket: t)
        c.forgetSession()
        c.ask("b")
        #expect(c.resumeID == nil)
    }
}
