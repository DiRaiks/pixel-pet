import Foundation
import Testing
import PetCore
@testable import PetIntegrations

/// Runs the real shell hook (sh + nc) against a real EventServer.
@Suite(.serialized) struct HookScriptTests {
    let home = "/tmp/pphome-\(UUID().uuidString.prefix(8))"
    var script: String { home + "/.pixelpet/bin/pixelpet-hook" }
    var socket: String { home + "/.pixelpet/pet.sock" }

    init() throws {
        try FileManager.default.createDirectory(atPath: home + "/.pixelpet/bin", withIntermediateDirectories: true)
        try HookInstaller.script.write(toFile: script, atomically: true, encoding: .utf8)
    }

    func cleanUp() { try? FileManager.default.removeItem(atPath: home) }

    @discardableResult
    func runHook(_ payload: String, asInternal: Bool = false) throws -> (status: Int32, seconds: Double) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script]
        var env = ["HOME": home, "PATH": "/usr/bin:/bin"]
        if asInternal { env["PIXELPET_INTERNAL"] = "1" }
        p.environment = env
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        let start = Date()
        try p.run()
        // The script may exit without reading its input (internal sessions): no SIGPIPE for the test run.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? input.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
        try input.fileHandleForWriting.close()
        p.waitUntilExit()
        return (p.terminationStatus, Date().timeIntervalSince(start))
    }

    @Test func forwardsPayloadToServer() async throws {
        let inbox = Inbox()
        let server = EventServer(path: socket) { inbox.add($0) }
        try server.start()
        defer { server.stop(); cleanUp() }
        let payload = #"{"hook_event_name":"Stop","session_id":"s1"}"#
        #expect(try runHook(payload).status == 0)
        for _ in 0..<100 where inbox.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        // The hook adds where the session runs (empty here); the rest arrives as sent.
        #expect(inbox.all.map { String(decoding: $0, as: UTF8.self) }
                == [#"{"pixelpet_app":"","pixelpet_term":"","hook_event_name":"Stop","session_id":"s1"}"#])
    }

    @Test func internalSessionsAreNotForwarded() async throws {
        let inbox = Inbox()
        let server = EventServer(path: socket) { inbox.add($0) }
        try server.start()
        defer { server.stop(); cleanUp() }
        // A big payload proves stdin is drained even on the early-exit path (no SIGPIPE for the writer).
        let big = String(repeating: "x", count: 1_000_000)
        #expect(try runHook(big, asInternal: true).status == 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(inbox.all.isEmpty)
    }

    @Test func withoutPetItExitsQuicklyAndCleanly() throws {
        defer { cleanUp() }
        let result = try runHook(#"{"hook_event_name":"Stop","session_id":"s1"}"#)
        #expect(result.status == 0)
        #expect(result.seconds < 0.5)
    }
}
