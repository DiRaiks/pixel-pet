import Foundation
import Testing
@testable import PetIntegrations

@Suite struct ClaudeProcessTests {
    /// A claude that exits without reading its input (a crash, a bad flag) used to kill the whole app with
    /// SIGPIPE while the text was still being written; now the write just fails.
    @Test func childExitingBeforeReadingStdinDoesNotKillUs() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-sigpipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("claude")
        try "#!/bin/sh\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        // Far more than a pipe buffer holds, so the writer is still writing when the reader is gone.
        let input = Data(repeating: UInt8(ascii: "x"), count: 4 << 20)
        let started = await ClaudeProcess.run(claude: script, arguments: [], stdin: input, timeout: 10, killAfter: 1,
                                              environment: [:], onLine: { _ in })
        #expect(started)
        // Give the background writer time to hit the closed pipe.
        try await Task.sleep(for: .milliseconds(300))
    }
}
