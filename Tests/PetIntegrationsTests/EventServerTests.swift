import Foundation
import Testing
@testable import PetIntegrations

final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []
    func add(_ d: Data) { lock.lock(); items.append(d); lock.unlock() }
    var all: [Data] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct EventServerTests {
    let path = "/tmp/pp-test-\(UUID().uuidString.prefix(8)).sock"

    func send(_ text: String) throws {
        try SocketClient.send(Data(text.utf8), to: path)
    }

    @Test func receivesOnePayloadPerConnection() async throws {
        let inbox = Inbox()
        let server = EventServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }

        for i in 0..<3 { try send(#"{"n":\#(i)}"#) }
        for _ in 0..<100 where inbox.all.count < 3 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(inbox.all.map { String(decoding: $0, as: UTF8.self) }.sorted() == [#"{"n":0}"#, #"{"n":1}"#, #"{"n":2}"#])
    }

    @Test func socketIsOwnerOnlyAndRemovedOnStop() throws {
        let server = EventServer(path: path) { _ in }
        try server.start()
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func doesNotStealASocketWithALiveListener() throws {
        let first = EventServer(path: path) { _ in }
        try first.start()
        defer { first.stop() }
        #expect(throws: EventServer.Error.self) { try EventServer(path: path) { _ in }.start() }
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func replacesDeadSocketButRefusesRegularFile() throws {
        try makeDeadSocket(at: path)
        let server = EventServer(path: path) { _ in }
        try server.start()
        server.stop()

        FileManager.default.createFile(atPath: path, contents: Data("keep".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: EventServer.Error.self) { try EventServer(path: path) { _ in }.start() }
    }

    @Test func slowClientDoesNotBlockOthers() async throws {
        let inbox = Inbox()
        let server = EventServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }
        let slow = try openTrickle(to: path)
        defer { close(slow) }
        try send(#"{"fast":1}"#)
        let start = Date()
        for _ in 0..<150 where !inbox.all.contains(Data(#"{"fast":1}"#.utf8)) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(inbox.all.contains(Data(#"{"fast":1}"#.utf8)))
        #expect(Date().timeIntervalSince(start) < EventServer.connectionDeadline + 1)
    }

    @Test func largePayloadArrivesWhole() async throws {
        let inbox = Inbox()
        let server = EventServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }
        let big = "{\"x\":\"" + String(repeating: "a", count: 3_000_000) + "\"}"
        try send(big)
        for _ in 0..<150 where inbox.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(inbox.all.first?.count == big.utf8.count)
    }
}

/// A socket file with nobody listening, like the one a crashed pet leaves behind.
func makeDeadSocket(at path: String) throws {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        let bytes = Array(path.utf8)
        buf.copyBytes(from: bytes)
        buf[bytes.count] = 0
    }
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    close(fd)
    #expect(rc == 0)
}

/// Connects and sends one byte, then goes quiet: a client that never finishes.
func openTrickle(to path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        let bytes = Array(path.utf8)
        buf.copyBytes(from: bytes)
        buf[bytes.count] = 0
    }
    _ = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    _ = write(fd, "{", 1)
    return fd
}
