import Foundation
import Testing
import PetCore
@testable import PetIntegrations

@Suite struct ClaudeAskTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-ask-\(UUID().uuidString)")

    func fake(_ body: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("claude")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func argumentsPersistTheSessionAndResumeWhenAsked() {
        let first = ClaudeAsk.arguments(model: "haiku", resume: nil)
        #expect(first.first == "-p")
        #expect(!first.contains("--no-session-persistence"))
        #expect(!first.contains("--resume"))
        #expect(first.contains("--append-system-prompt"))
        #expect(first.firstIndex(of: "--tools").map { first[$0 + 1] } == "")
        let next = ClaudeAsk.arguments(model: "haiku", resume: "s1")
        #expect(next.firstIndex(of: "--resume").map { next[$0 + 1] } == "s1")
    }

    @Test func streamsSessionTextAndFinishesAtMessageStop() async throws {
        // The fake keeps running after message_stop (like the CLI's turn summary); done must fire before exit.
        let claude = try fake("""
        q=$(cat)
        case "$*" in *"$q"*) exit 4;; esac
        echo '{"type":"system","subtype":"init","session_id":"s-42"}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Ответ"}}}'
        echo '{"type":"stream_event","event":{"type":"message_stop"}}'
        sleep 2
        echo '{"type":"result","subtype":"success","is_error":false,"result":"Ответ"}'
        """)
        let events = Lines()
        let start = Date()
        let doneAt = Lines()
        let result = await ClaudeChat.run(
            claude: claude, arguments: ClaudeAsk.arguments(model: "haiku", resume: nil), input: "секретный вопрос",
            onEvent: { event in
                switch event {
                case .session(let id): events.add("session \(id)")
                case .text(let text): events.add("text \(text)")
                case .done(let text):
                    events.add("done \(text)")
                    doneAt.add(String(Date().timeIntervalSince(start) < 1.5))
                case .limits: break
                }
            })
        #expect(result == .success("Ответ"))
        #expect(events.all == ["session s-42", "text Ответ", "done Ответ"])
        #expect(doneAt.all == ["true"])
    }
}

@Suite struct ClaudeChatResultTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-chat-\(UUID().uuidString)")

    @Test func resultWithoutDeltasStillCompletesWithTheText() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let claude = root.appendingPathComponent("claude")
        try "#!/bin/sh\ncat >/dev/null\necho '{\"type\":\"result\",\"is_error\":false,\"result\":\"Короткий ответ\"}'\n"
            .write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        let done = Lines()
        let result = await ClaudeChat.run(claude: claude, arguments: [], input: "q") { event in
            if case .done(let text) = event { done.add(text) }
        }
        #expect(result == .success("Короткий ответ"))
        #expect(done.all == ["Короткий ответ"])
    }
}
