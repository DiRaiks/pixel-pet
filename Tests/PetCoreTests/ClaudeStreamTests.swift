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
