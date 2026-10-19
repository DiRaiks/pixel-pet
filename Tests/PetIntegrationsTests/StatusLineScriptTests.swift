import Foundation
import Testing
import PetCore
@testable import PetIntegrations

@Suite(.serialized) struct StatusLineScriptTests {
    let home = "/tmp/ppsl-\(UUID().uuidString.prefix(8))"
    var script: String { home + "/.pixelpet/bin/pixelpet-statusline" }

    init() throws {
        try FileManager.default.createDirectory(atPath: home + "/.pixelpet/bin", withIntermediateDirectories: true)
        try HookInstaller.statusLineScript.write(toFile: script, atomically: true, encoding: .utf8)
    }

    func run(_ payload: String, locale: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script]
        var env = ["HOME": home, "PATH": "/usr/bin:/bin"]
        if let locale { env["LC_ALL"] = locale }
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        p.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test func printsCompactLineAndForwardsSnapshot() async throws {
        defer { try? FileManager.default.removeItem(atPath: home) }
        let inbox = Inbox()
        let server = EventServer(path: home + "/.pixelpet/pet.sock") { inbox.add($0) }
        try server.start()
        defer { server.stop() }
        let payload = #"{"session_id":"s","model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":42.4},"rate_limits":{"five_hour":{"used_percentage":12.6,"resets_at":1},"seven_day":{"used_percentage":3,"resets_at":2}}}"#
        #expect(try run(payload) == "Opus 5.5 · ctx 42% · 5h 13% · 7d 3%\n")
        for _ in 0..<100 where inbox.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(inbox.all.first.map { String(decoding: $0, as: UTF8.self) } == payload)
    }

    @Test func worksWithoutPetAndMissingFields() throws {
        defer { try? FileManager.default.removeItem(atPath: home) }
        #expect(try run(#"{"session_id":"s"}"#) == "Claude\n")
    }

    @Test func commaDecimalLocaleStillPrintsPercentages() throws {
        defer { try? FileManager.default.removeItem(atPath: home) }
        let payload = #"{"session_id":"s","model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":42.4}}"#
        #expect(try run(payload, locale: "de_DE.UTF-8") == "Opus 5.5 · ctx 42%\n")
    }
}
