import Foundation
import Testing
@testable import PetIntegrations

@Suite struct TouchWatcherTests {
    final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-touch-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static let line = #"{"processImagePath":"/x/usbsmartcardreaderd","eventMessage":"Time extension received"}"#

    /// Matching lines reach the handler, others don't, also when a line arrives in two pieces.
    @Test func reportsTouchRequestsFromTheStream() async throws {
        let fake = try script("""
        echo 'Filtering the log data using …'
        echo '\(Self.line)'
        printf '%s' '{"processImagePath":"/x/usbsmartcardreaderd",'
        sleep 0.2
        echo '"eventMessage":"Time extension received"}'
        echo '{"processImagePath":"/x/other","eventMessage":"Time extension received"}'
        exec sleep 5
        """)
        let count = Count()
        let watcher = TouchWatcher(executable: fake, arguments: []) { _ in count.add() }
        watcher.start()
        defer { watcher.stop() }
        for _ in 0..<40 where count.value < 2 { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(count.value == 2)
    }

    /// A stream that ends on its own comes back.
    @Test func restartsAStreamThatEnds() async throws {
        let fake = try script("echo '\(Self.line)'\n")
        let count = Count()
        let watcher = TouchWatcher(executable: fake, arguments: [], restartDelay: 0.1) { _ in count.add() }
        watcher.start()
        defer { watcher.stop() }
        for _ in 0..<60 where count.value < 3 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(count.value >= 3)
    }

    @Test func missingExecutableDoesNotCrash() async throws {
        let watcher = TouchWatcher(executable: URL(fileURLWithPath: "/nonexistent/log"), arguments: [],
                                   restartDelay: 0.05) { _ in }
        watcher.start()
        try await Task.sleep(for: .milliseconds(300))
        watcher.stop()
    }

    /// The watchdog ends `log stream` itself when the app it was started for is gone.
    @Test func watchdogEndsTheStreamWhenTheAppIsGone() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-wd-\(UUID().uuidString)")
        let fakeLog = try script("echo $$ > '\(marker.path)'\nexec sleep 30\n")
        // Stand-in for the app: a process that exits after a moment.
        let app = Process()
        app.executableURL = URL(fileURLWithPath: "/bin/sleep")
        app.arguments = ["1"]
        try app.run()
        let shell = TouchWatcher.watchdog.replacingOccurrences(of: "/usr/bin/log", with: fakeLog.path)
        let dog = Process()
        dog.executableURL = URL(fileURLWithPath: "/bin/sh")
        dog.arguments = ["-c", shell, "pixelpet-touch", String(app.processIdentifier)]
        try dog.run()
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: marker.path) { try await Task.sleep(for: .milliseconds(50)) }
        let pid = Int32((try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        #expect(pid > 0)
        app.waitUntilExit()
        for _ in 0..<160 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(kill(pid, 0) != 0, "the stream outlived the app")
    }

    @Test func stopEndsTheStream() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-touch-\(UUID().uuidString)")
        let fake = try script("echo $$ > '\(marker.path)'\nexec sleep 30\n")
        let watcher = TouchWatcher(executable: fake, arguments: []) { _ in }
        watcher.start()
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: marker.path) { try await Task.sleep(for: .milliseconds(50)) }
        let pid = Int32((try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        #expect(pid > 0)
        watcher.stop()
        try await Task.sleep(for: .milliseconds(300))
        #expect(kill(pid, 0) != 0, "the stream process is gone")
    }
}
