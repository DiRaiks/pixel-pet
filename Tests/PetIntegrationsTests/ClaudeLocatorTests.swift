import Foundation
import Testing
import PetCore
@testable import PetIntegrations

@Suite struct ClaudeLocatorTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-loc-\(UUID().uuidString)")

    func fakeBinary(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func bundled(_ version: String) -> URL {
        root.appendingPathComponent("app/\(version)/abc123/claude.app/Contents/MacOS/claude")
    }

    @Test func picksNewestBundledVersion() throws {
        for v in ["2.1.51", "2.1.299", "2.1.300"] { try fakeBinary(bundled(v)) }
        let found = ClaudeLocator.find(override: nil, path: "", appSupport: root.appendingPathComponent("app"))
        #expect(found == bundled("2.1.300"))
    }

    @Test func pathBeatsBundleAndOverrideBeatsPath() throws {
        try fakeBinary(bundled("2.1.299"))
        let onPath = root.appendingPathComponent("bin/claude")
        try fakeBinary(onPath)
        let custom = root.appendingPathComponent("custom/claude")
        try fakeBinary(custom)
        let app = root.appendingPathComponent("app")
        #expect(ClaudeLocator.find(override: nil, path: "/nope:" + onPath.deletingLastPathComponent().path, appSupport: app) == onPath)
        #expect(ClaudeLocator.find(override: custom.path, path: onPath.deletingLastPathComponent().path, appSupport: app) == custom)
    }

    @Test func nothingFound() {
        #expect(ClaudeLocator.find(override: "/nope/claude", path: "/nope", appSupport: root) == nil)
    }
}

@Suite struct LimitsProbeTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-probe-\(UUID().uuidString)")

    @Test func argumentsAreCheapAndIsolated() {
        let args = LimitsProbe.arguments
        #expect(args.contains("-p"))
        #expect(args.contains("haiku"))
        #expect(args.contains("stream-json"))
        #expect(args.contains("--no-session-persistence"))
        let sources = args.firstIndex(of: "--setting-sources").map { args[$0 + 1] }
        #expect(sources == "project")
        let tools = args.firstIndex(of: "--tools").map { args[$0 + 1] }
        #expect(tools == "")
    }

    @Test func parsesLimitsFromFakeClaude() async throws {
        let fake = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        [ "$PIXELPET_INTERNAL" = 1 ] || exit 3
        echo '{"type":"system","subtype":"init"}'
        echo '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.5,"resetsAt":1792416600}}}}'
        echo '{"type":"result","subtype":"success"}'
        """
        try script.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let limits = await LimitsProbe.run(claude: fake, timeout: 10)
        #expect(limits?.fiveHour?.usedPercent == 50)
    }

    @Test func hangingClaudeTimesOut() async throws {
        let fake = root.appendingPathComponent("slow")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/sh\nsleep 30\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let start = Date()
        #expect(await LimitsProbe.run(claude: fake, timeout: 1) == nil)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func stripsApiCredentialsSoTheSubscriptionIsUsed() async throws {
        let fake = root.appendingPathComponent("envcheck")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        [ -z "$ANTHROPIC_API_KEY$ANTHROPIC_AUTH_TOKEN$CLAUDE_CODE_USE_BEDROCK$CLAUDE_CODE_USE_VERTEX" ] || exit 4
        echo '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.1,"resetsAt":1792416600}}}}'
        """
        try script.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let env = ["ANTHROPIC_API_KEY": "sk-test", "ANTHROPIC_AUTH_TOKEN": "t", "CLAUDE_CODE_USE_BEDROCK": "1", "PATH": "/usr/bin:/bin"]
        #expect(await LimitsProbe.run(claude: fake, timeout: 10, environment: env)?.fiveHour?.usedPercent == 10)
    }

    @Test func claudeIgnoringSigtermIsKilled() async throws {
        let fake = root.appendingPathComponent("stubborn")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/sh\ntrap '' TERM\nwhile :; do sleep 1; done\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let start = Date()
        #expect(await LimitsProbe.run(claude: fake, timeout: 1, killAfter: 1) == nil)
        #expect(Date().timeIntervalSince(start) < 6)
    }
}
