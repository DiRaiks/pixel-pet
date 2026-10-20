import Foundation
import Testing
import PetCore
@testable import PetIntegrations

/// The real hook script and a real EventServer: a permission request waits on the socket for the pet's
/// answer and prints it; everything else stays fire-and-forget.
@Suite(.serialized) struct PermissionHookTests {
    let home = "/tmp/ppperm-\(UUID().uuidString.prefix(8))"
    var script: String { home + "/.pixelpet/bin/pixelpet-hook" }
    var socket: String { home + "/.pixelpet/pet.sock" }

    init() throws {
        try FileManager.default.createDirectory(atPath: home + "/.pixelpet/bin", withIntermediateDirectories: true)
        try HookInstaller.script.write(toFile: script, atomically: true, encoding: .utf8)
    }

    func cleanUp() { try? FileManager.default.removeItem(atPath: home) }

    static let request = #"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/w/app","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Clean"}}"#

    /// Runs the hook with `payload`; returns what it printed and how long it took.
    func runHook(_ payload: String, env extra: [String: String] = [:]) throws -> (output: String, seconds: Double) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script]
        p.environment = ["HOME": home, "PATH": "/usr/bin:/bin"].merging(extra) { $1 }
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        let start = Date()
        try p.run()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? input.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
        try input.fileHandleForWriting.close()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: printed, as: UTF8.self), Date().timeIntervalSince(start))
    }

    /// Starts a server whose handler answers a waiting hook with `answer` after `delay`.
    func server(answer: @escaping @Sendable (Data) -> Data?, delay: TimeInterval = 0.2,
                received: Box = Box()) throws -> EventServer {
        let server = EventServer(path: socket) { data, reply in
            received.set(data)
            guard let reply else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { reply.send(answer(data)) }
        }
        try server.start()
        return server
    }

    final class Held: @unchecked Sendable {
        var reply: HookReply?
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?
        func set(_ data: Data) { lock.withLock { value = data } }
        var data: Data? { lock.withLock { value } }
    }

    @Test func allowIsPrintedForClaudeCode() throws {
        defer { cleanUp() }
        let prompt = PermissionPrompt.parse(Data(Self.request.utf8))!
        let allow = PermissionAnswer.allow.hookOutput(for: prompt)!
        let received = Box()
        let server = try server(answer: { _ in allow }, received: received)
        defer { server.stop() }
        let run = try runHook(Self.request, env: ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"])
        let json = try JSONSerialization.jsonObject(with: Data(run.output.utf8)) as? [String: Any]
        let decision = (json?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        // The pet learns where the session runs.
        let sent = received.data.flatMap { PermissionPrompt.parse($0) }
        #expect(sent?.host?.bundleID == "com.apple.Terminal")
        #expect(sent?.subject == "rm -rf build")
    }

    /// Letting go (no answer, the card closed, the setting off): nothing printed, the usual prompt follows.
    @Test func lettingGoPrintsNothing() throws {
        defer { cleanUp() }
        let server = try server(answer: { _ in nil })
        defer { server.stop() }
        let run = try runHook(Self.request)
        #expect(run.output.isEmpty)
        #expect(run.seconds < 3)
    }

    @Test func noPetMeansNoWait() throws {
        defer { cleanUp() }
        let run = try runHook(Self.request)
        #expect(run.output.isEmpty)
        #expect(run.seconds < 1)
    }

    /// A server that never answers: the hook's own deadline lets go before Claude Code's timeout.
    @Test func hookOutlivesNeitherServerNorClaude() {
        #expect(EventServer.replyDeadline < Double(PermissionWait.ncTimeout))
        #expect(PermissionWait.window < EventServer.replyDeadline)
        #expect(PermissionWait.ncTimeout < PermissionWait.hookTimeout)
    }

    /// Ordinary events don't wait and print nothing, even if the server would answer.
    @Test func otherEventsStayFireAndForget() throws {
        defer { cleanUp() }
        let server = try server(answer: { _ in Data("nope".utf8) }, delay: 2)
        defer { server.stop() }
        let run = try runHook(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash"}"#)
        #expect(run.output.isEmpty)
        #expect(run.seconds < 1.5)
    }

    /// A hook killed while waiting (Esc in the terminal, the session ending) is noticed, so its card goes.
    @Test func goneHookIsNoticed() throws {
        defer { cleanUp() }
        let noticed = Box()
        let held = Held()
        let server = EventServer(path: socket) { _, reply in
            // The app keeps the reply while the card is up; so does this test.
            held.reply = reply
            reply?.onGone { noticed.set(Data("gone".utf8)) }
        }
        try server.start()
        defer { server.stop() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "printf '%s' '\(Self.request)' | nc -U -w 30 '\(socket)' >/dev/null & sleep 0.4; kill $!"]
        try p.run()
        p.waitUntilExit()
        let deadline = Date().addingTimeInterval(3)
        while noticed.data == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(noticed.data != nil)
    }

    /// The env values can't break out of the JSON string the hook adds them to.
    @Test func hostileEnvironmentStaysInsideTheString() throws {
        defer { cleanUp() }
        let received = Box()
        let server = try server(answer: { _ in nil }, received: received)
        defer { server.stop() }
        _ = try runHook(Self.request, env: ["TERM_PROGRAM": #"x","tool_name":"Evil"#, "__CFBundleIdentifier": #"a\"};rm -rf /"#])
        let json = received.data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(json?["tool_name"] as? String == "Bash")
        #expect((json?["pixelpet_term"] as? String)?.contains("\"") == false)
    }

    /// Spacing and line breaks don't decide anything any more: the server reads the JSON.
    @Test func prettyPrintedRequestStillWaits() throws {
        defer { cleanUp() }
        let pretty = "{\n  \"hook_event_name\" : \"PermissionRequest\",\n  \"session_id\": \"s1\",\n  \"tool_name\": \"Bash\",\n  \"tool_input\": {\"command\": \"ls\"}\n}"
        let server = try server(answer: { data in PermissionPrompt.parse(data).flatMap { PermissionAnswer.deny.hookOutput(for: $0) } })
        defer { server.stop() }
        let run = try runHook(pretty)
        #expect(run.output.contains("\"deny\""))
    }

    @Test func replyIsSentOnceAndOnlyToARealRequest() {
        #expect(EventServer.waitsForReply(Data(Self.request.utf8)))
        #expect(!EventServer.waitsForReply(Data("not json".utf8)))
        #expect(!EventServer.waitsForReply(Data(#"{"hook_event_name":"PreToolUse"}"#.utf8)))
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let reply = HookReply(fd: fds[0], deadline: 30)
        reply.send(Data("first".utf8))
        reply.send(Data("second".utf8))
        #expect(!reply.isOpen)
        var buffer = [UInt8](repeating: 0, count: 64)
        let n = read(fds[1], &buffer, buffer.count)
        #expect(String(decoding: buffer[0..<max(n, 0)], as: UTF8.self) == "first")
        close(fds[1])
    }
}
