import Foundation
import Testing
import PetCore
@testable import PetIntegrations

final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct ClaudeTranslatorTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-ct-\(UUID().uuidString)")

    func fake(_ body: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("claude")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func textGoesThroughStdinAndStreamsBack() async throws {
        // The fake proves the text arrived on stdin (not argv) and streams it back in two deltas.
        let claude = try fake("""
        [ "$PIXELPET_INTERNAL" = 1 ] || exit 3
        input=$(cat)
        case "$*" in *"$input"*) exit 4;; esac
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Пик"}}}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"сель"}}}'
        echo '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.2,"resetsAt":1792416600}}}}'
        printf '{"type":"result","subtype":"success","is_error":false,"result":"%s"}\\n' "$input"
        """)
        let partial = Lines()
        let seenLimits = Lines()
        let result = await ClaudeTranslation.run(claude: claude, text: "Pixel secret", target: "ru",
                                                 onText: { partial.add($0) },
                                                 onLimits: { seenLimits.add("\($0.fiveHour?.usedPercent ?? -1)") })
        #expect(result == .success("Pixel secret"))
        #expect(partial.all == ["Пик", "Пиксель"])
        #expect(seenLimits.all == ["20.0"])
    }

    @Test func failuresAreReported() async throws {
        let claude = try fake("cat >/dev/null\necho '{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in\"}'\n")
        let result = await ClaudeTranslation.run(claude: claude, text: "x", target: "ru", onText: { _ in }, onLimits: { _ in })
        #expect(result == .failure(.claude("Not logged in")))
    }

    @Test func cancellationStopsTheProcess() async throws {
        let claude = try fake("cat >/dev/null\nsleep 30\n")
        let start = Date()
        let task = Task { await ClaudeTranslation.run(claude: claude, text: "x", target: "ru", onText: { _ in }, onLimits: { _ in }) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
        #expect(Date().timeIntervalSince(start) < 6)
    }

    @Test func argumentsAreIsolated() {
        let args = ClaudeTranslation.arguments(target: "ru", model: "sonnet")
        #expect(args.first == "-p")
        #expect(args.contains("--no-session-persistence"))
        #expect(args.firstIndex(of: "--setting-sources").map { args[$0 + 1] } == "project")
        #expect(args.firstIndex(of: "--tools").map { args[$0 + 1] } == "")
        #expect(args.firstIndex(of: "--model").map { args[$0 + 1] } == "sonnet")
        #expect(args.contains("--include-partial-messages"))
    }
}
