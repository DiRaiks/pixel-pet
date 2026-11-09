import Foundation
import Testing
import PetCore
@testable import PetIntegrations

@Suite(.serialized) struct CodexWatcherTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-codex-\(UUID().uuidString)")
    static let id = "01a144b6-fc33-7231-a0da-63a9a29ce005"

    func line(_ type: String, _ payload: [String: Any], at time: Date = Date()) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "timestamp": ISO8601DateFormatter().string(from: time), "type": type, "payload": payload,
        ])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    var meta: String { line("session_meta", ["id": Self.id, "cwd": "/w/app", "thread_source": "user"]) }
    func task(_ type: String, at time: Date = Date()) -> String { line("event_msg", ["type": type, "turn_id": "t1"], at: time) }
    func spawned(_ id: String, by parent: String) -> String {
        line("session_meta", ["id": id, "cwd": "/w/app", "thread_source": "subagent",
                              "source": ["subagent": ["thread_spawn": ["parent_thread_id": parent, "depth": 1]]]])
    }
    func events(_ inbox: Inbox) -> [AgentEvent] {
        inbox.all.flatMap(\.outputs).compactMap { if case .event(let e, _) = $0 { e } else { nil } }
    }

    func file(_ id: String = id) throws -> URL {
        let dir = root.appendingPathComponent("2026/10/19")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rollout-2026-10-19T16-00-00-\(id).jsonl")
    }

    func append(_ text: String, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    /// Collects batches; waits up to `timeout` for `count` events in total.
    final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var batches: [CodexWatcher.Batch] = []
        func add(_ b: CodexWatcher.Batch) { lock.lock(); batches.append(b); lock.unlock() }
        var all: [CodexWatcher.Batch] { lock.lock(); defer { lock.unlock() }; return batches }
        func kinds(replay: Bool) -> [AgentEvent.Kind] {
            all.filter { $0.isReplay == replay }.flatMap(\.outputs).compactMap {
                if case .event(let e, _) = $0 { e.kind } else { nil }
            }
        }
        func wait(until done: () -> Bool, timeout: TimeInterval = 5) async {
            let end = Date().addingTimeInterval(timeout)
            while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
        }
    }

    @Test func catchesUpWithARecentFileThenFollowsAppends() async throws {
        let url = try file()
        try append(meta + task("task_started"), to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        await inbox.wait { inbox.kinds(replay: true).count >= 2 }
        #expect(inbox.kinds(replay: true) == [.sessionStart(model: nil), .promptSubmitted])

        // Half a line first: nothing until the rest of it arrives.
        let done = task("task_complete")
        try append(String(done.prefix(20)), to: url)
        try await Task.sleep(for: .milliseconds(600))
        #expect(inbox.kinds(replay: false).isEmpty)
        try append(String(done.dropFirst(20)), to: url)
        await inbox.wait { !inbox.kinds(replay: false).isEmpty }
        #expect(inbox.kinds(replay: false) == [.stopped])
    }

    /// Codex keeps its session file open for the whole session, and FSEvents goes quiet about a file that
    /// stays open after its first event: appends must still be seen while the writer holds the file.
    @Test func followsAppendsWhileTheWriterKeepsTheFileOpen() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let url = try file()
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        try writer.write(contentsOf: Data((meta + task("task_started")).utf8))
        await inbox.wait { inbox.kinds(replay: false).contains(.promptSubmitted) }
        for _ in 0..<5 {
            try writer.write(contentsOf: Data(line("event_msg", ["type": "item_completed", "turn_id": "t1"]).utf8))
            try await Task.sleep(for: .milliseconds(200))
        }
        try writer.write(contentsOf: Data(task("task_complete").utf8))
        await inbox.wait { inbox.kinds(replay: false).contains(.stopped) }
        #expect(inbox.kinds(replay: false).contains(.stopped))
    }

    @Test func picksUpASessionThatStartsLater() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let url = try file("01a144b6-fc33-7231-a0da-63a9a29ce006")
        try append(line("session_meta", ["id": "01a144b6-fc33-7231-a0da-63a9a29ce006", "cwd": "/w/new"]) + task("task_started"), to: url)
        await inbox.wait { inbox.kinds(replay: false).count >= 2 }
        #expect(inbox.kinds(replay: false) == [.sessionStart(model: nil), .promptSubmitted])
    }

    /// A big file: the metadata comes from its first line, the state from its tail; the cut-off line the tail
    /// starts in is dropped rather than parsed as garbage.
    @Test func bigFileIsReadByHeadAndTail() async throws {
        let url = try file()
        let filler = line("response_item", ["type": "message", "text": String(repeating: "x", count: 4000)])
        var text = meta + task("task_complete")
        while text.utf8.count < CodexWatcher.tailBytes * 2 { text += filler }
        text += task("task_started")
        try append(text, to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        await inbox.wait { inbox.kinds(replay: true).contains(.promptSubmitted) }
        let kinds = inbox.kinds(replay: true)
        #expect(kinds.first == .sessionStart(model: nil))
        #expect(kinds.last == .promptSubmitted)
        #expect(!kinds.contains(.stopped), "the old turn's end is outside the tail")
    }

    @Test func helperFilesStaySilent() async throws {
        let url = try file()
        try append(line("session_meta", ["id": Self.id, "cwd": "/w/app", "thread_source": "guardian_review",
                                         "source": ["subagent": ["other": "guardian"]]]), to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(400))
        for _ in 0..<3 {
            try append(task("task_started"), to: url)
            try await Task.sleep(for: .milliseconds(400))
        }
        #expect(inbox.all.isEmpty)
    }

    /// A spawned agent's file is followed like any other; what it does goes to its parent's session.
    @Test func spawnedAgentFilesReportToTheParent() async throws {
        let child = "01a19300-0000-7000-8000-000000000001"
        try append(meta, to: try file())
        let url = try file(child)
        try append(spawned(child, by: Self.id), to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(400))
        try append(task("task_started"), to: url)
        await inbox.wait { !inbox.kinds(replay: false).isEmpty }
        try append(task("task_complete"), to: url)
        await inbox.wait { inbox.kinds(replay: false).count >= 2 }
        #expect(inbox.kinds(replay: false) == [.subagentStarted(id: child), .subagentStopped(id: child)])
        #expect(Set(events(inbox).map(\.sessionID)) == [Self.id])
    }

    /// An agent spawned by a spawned agent counts for the session at the top, whichever file is read first.
    @Test func nestedAgentsReportToTheTopSession() async throws {
        let child = "01a19300-0000-7000-8000-000000000001", grandchild = "01a19300-0000-7000-8000-000000000002"
        let grandURL = try file(grandchild)
        try append(spawned(grandchild, by: child) + task("task_started"), to: grandURL)
        try append(spawned(child, by: Self.id) + task("task_started"), to: try file(child))
        try append(meta, to: try file())
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        await inbox.wait { inbox.kinds(replay: true).count >= 3 }
        try append(task("task_complete"), to: grandURL)
        await inbox.wait { !inbox.kinds(replay: false).isEmpty }
        #expect(Set(events(inbox).map(\.sessionID)) == [Self.id])
        let replay = inbox.kinds(replay: true).filter(\.isSubagentChange)
        #expect(replay.count == 2)
        #expect(replay.contains(.subagentStarted(id: child)))
        #expect(replay.contains(.subagentStarted(id: grandchild)))
        #expect(inbox.kinds(replay: false) == [.subagentStopped(id: grandchild)])
    }

    /// An agent whose parent has no file (or a helper thread for a parent) shows nothing: no session is made up.
    @Test func agentWithoutAParentFileShowsNothing() async throws {
        let child = "01a19300-0000-7000-8000-000000000001"
        let url = try file(child)
        try append(spawned(child, by: "01a19300-0000-7000-8000-0000000000ff"), to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(400))
        try append(task("task_started"), to: url)
        try await Task.sleep(for: .milliseconds(600))
        #expect(inbox.all.flatMap(\.outputs).isEmpty)
    }

    /// A parent waiting on its agent may write nothing for longer than the catch-up window: the agent's
    /// first line opens the parent's file, so it shows with its folder.
    @Test func quietParentIsOpenedForItsAgent() async throws {
        let child = "01a19300-0000-7000-8000-000000000001"
        let parentURL = try file()
        try append(meta, to: parentURL)
        let old = Date().addingTimeInterval(-3 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: parentURL.path)
        let url = try file(child)
        try append(spawned(child, by: Self.id), to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(400))
        try append(task("task_started"), to: url)
        await inbox.wait { inbox.kinds(replay: false).contains(.subagentStarted(id: child)) }
        let live = events(inbox)
        #expect(live.map(\.kind) == [.sessionStart(model: nil), .subagentStarted(id: child)])
        #expect(Set(live.map(\.sessionID)) == [Self.id])
        #expect(live.first?.cwd == "/w/app")
    }

    /// At start, files are read one after another; the batch goes out in time order, so a parent whose turn
    /// ended after its agent started isn't left idle with the agent counted, whichever file came first.
    @Test func catchUpIsInTimeOrder() async throws {
        let child = "01a19300-0000-7000-8000-000000000001"
        let t0 = Date().addingTimeInterval(-60)
        try append(meta + task("task_started", at: t0) + task("task_complete", at: t0.addingTimeInterval(10)), to: try file())
        try append(spawned(child, by: Self.id) + task("task_started", at: t0.addingTimeInterval(5))
                   + task("task_complete", at: t0.addingTimeInterval(20)), to: try file(child))
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        await inbox.wait { inbox.kinds(replay: true).count >= 5 }
        let kinds = inbox.kinds(replay: true).filter { $0 != .sessionStart(model: nil) }
        #expect(kinds == [.promptSubmitted, .subagentStarted(id: child), .stopped, .subagentStopped(id: child)])
    }

    /// Without Codex there is no ~/.codex: the watcher must not create it.
    @Test func missingRootIsNotCreated() async throws {
        let missing = root.appendingPathComponent("nope/sessions")
        let watcher = CodexWatcher(root: missing) { _ in }
        watcher.start()
        try await Task.sleep(for: .milliseconds(300))
        watcher.stop()
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func rewrittenFileStartsOver() async throws {
        let url = try file()
        try append(meta + task("task_started"), to: url)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        await inbox.wait { inbox.kinds(replay: true).count >= 2 }
        // Shorter than before: that is how a rewrite is told from an append.
        try Data((meta).utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(700))
        try append(task("turn_aborted"), to: url)
        await inbox.wait { inbox.kinds(replay: false).contains(.interrupted) }
        #expect(inbox.kinds(replay: false).contains(.interrupted))
    }

    @Test func chunkFromTheMiddleDropsItsPartialLine() {
        #expect(CodexWatcher.fromFirstFullLine(Data("tail of a line\n{\"a\":1}\n".utf8)) == Data("{\"a\":1}\n".utf8))
        #expect(CodexWatcher.fromFirstFullLine(Data("one giant line without end".utf8)).isEmpty)
    }

    @Test func oldFilesAreLeftAlone() async throws {
        let url = try file()
        try append(meta + task("task_started"), to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: url.path)
        let inbox = Inbox()
        let watcher = CodexWatcher(root: root, recentWindow: 1800) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(inbox.all.isEmpty)
    }
}

@Suite struct CodexLocatorTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-cxloc-\(UUID().uuidString)")

    func make(_ url: URL, native: Bool) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes: [UInt8] = native ? [0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0] : Array("#!/usr/bin/env node\n".utf8)
        try Data(bytes).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The npm `codex` is a Node script that can't run without Node on PATH; native copies win.
    @Test func skipsNodeScriptsAndPrefersNativeBinaries() throws {
        let script = root.appendingPathComponent("nvm/bin/codex")
        try make(script, native: false)
        let app = root.appendingPathComponent("ChatGPT.app/codex")
        try make(app, native: true)
        #expect(CodexLocator.find(path: script.deletingLastPathComponent().path, candidates: [app],
                                  releases: root.appendingPathComponent("none")) == app)
    }

    @Test func newestStandaloneReleaseIsTheFallback() throws {
        let releases = root.appendingPathComponent("releases")
        for v in ["0.136.0-aarch64-apple-darwin", "0.152.1-aarch64-apple-darwin", "0.99.0-aarch64-apple-darwin"] {
            try make(releases.appendingPathComponent("\(v)/codex"), native: true)
        }
        #expect(CodexLocator.find(path: "", candidates: [], releases: releases)
                == releases.appendingPathComponent("0.152.1-aarch64-apple-darwin/codex"))
        #expect(CodexLocator.find(path: "", candidates: [], releases: root.appendingPathComponent("none")) == nil)
    }
}
