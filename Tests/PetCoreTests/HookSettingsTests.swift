import Foundation
import Testing
@testable import PetCore

@Suite struct HookSettingsTests {
    let cmd = "/Users/a/.pixelpet/bin/pixelpet-hook"

    func groups(_ s: [String: Any], _ event: String) -> [[String: Any]] {
        ((s["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }

    @Test func installAddsEveryEventAndKeepsOtherKeys() throws {
        let out = try HookSettings.install(into: ["model": "opus", "$comment": "мой конфиг"], command: cmd)
        #expect(out["model"] as? String == "opus")
        #expect(out["$comment"] as? String == "мой конфиг")
        for event in HookSettings.events { #expect(groups(out, event).count == 1, "\(event)") }
        #expect(HookSettings.isInstalled(in: out, command: cmd))
    }

    @Test func installIsIdempotent() throws {
        let once = try HookSettings.install(into: [:], command: cmd)
        let twice = try HookSettings.install(into: once, command: cmd)
        #expect(groups(twice, "Stop").count == 1)
    }

    @Test func installKeepsForeignHooks() throws {
        let foreign: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let out = try HookSettings.install(into: foreign, command: cmd)
        #expect(groups(out, "Stop").count == 2)
    }

    @Test func uninstallRemovesOnlyOurs() throws {
        let foreign: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]], "x": 1]
        let out = try HookSettings.uninstall(from: HookSettings.install(into: foreign, command: cmd), command: cmd)
        #expect(groups(out, "Stop").count == 1)
        #expect(groups(out, "PreToolUse").isEmpty)
        #expect((out["hooks"] as? [String: Any])?.keys.sorted() == ["Stop"])
        #expect(out["x"] as? Int == 1)
        #expect(!HookSettings.isInstalled(in: out, command: cmd))
    }

    @Test func uninstallDropsEmptyHooksKey() throws {
        let out = try HookSettings.uninstall(from: HookSettings.install(into: [:], command: cmd), command: cmd)
        #expect(out["hooks"] == nil)
    }

    @Test func partialInstallIsNotInstalled() throws {
        var out = try HookSettings.install(into: [:], command: cmd)
        var hooks = out["hooks"] as! [String: Any]
        hooks.removeValue(forKey: "Stop")
        out["hooks"] = hooks
        #expect(!HookSettings.isInstalled(in: out, command: cmd))
    }
}

@Suite struct HookSettingsShapeTests {
    let cmd = "/x/pixelpet-hook"

    @Test func refusesUnexpectedHookShapesInsteadOfDroppingThem() {
        #expect(throws: HookSettings.Error.self) { try HookSettings.install(into: ["hooks": "oops"], command: cmd) }
        #expect(throws: HookSettings.Error.self) { try HookSettings.install(into: ["hooks": ["Stop": [1, 2]]], command: cmd) }
        #expect(throws: HookSettings.Error.self) { try HookSettings.uninstall(from: ["hooks": ["Stop": "x"]], command: cmd) }
    }

    @Test func pinsTheEventNamesCheckedAgainstClaudeCode() {
        #expect(HookSettings.events == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                        "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart",
                                        "SubagentStop", "SessionEnd"])
    }

    @Test func commandIsShellQuoted() {
        #expect(HookInstaller.command(for: URL(fileURLWithPath: "/Users/My Name/.pixelpet/bin/pixelpet-hook"))
            == "'/Users/My Name/.pixelpet/bin/pixelpet-hook'")
    }
}

@Suite struct HookInstallerTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-hooks-\(UUID().uuidString)")
    var installer: HookInstaller {
        HookInstaller(settingsURL: dir.appendingPathComponent("claude/settings.json"),
                      scriptURL: dir.appendingPathComponent("pet/bin/pixelpet-hook"))
    }

    @Test func installWritesExecutableScriptAndBacksUpSettings() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude"), withIntermediateDirectories: true)
        let original = #"{"$comment":"Глобальные настройки","permissions":{"deny":["Bash(npm i:*)"]}}"#
        try Data(original.utf8).write(to: installer.settingsURL)

        try installer.install()

        let attrs = try FileManager.default.attributesOfItem(atPath: installer.scriptURL.path)
        #expect((attrs[.posixPermissions] as? Int ?? 0) & 0o111 != 0)
        #expect(try String(contentsOf: installer.scriptURL, encoding: .utf8).contains("PIXELPET_INTERNAL"))
        #expect(installer.isInstalled)
        let text = try String(contentsOf: installer.settingsURL, encoding: .utf8)
        #expect(text.contains("Глобальные настройки"))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("claude").path)
            .filter { $0.hasPrefix("settings.json.pixelpet-backup-") }
        #expect(backups.count == 1)
    }

    @Test func installCreatesMissingSettings() throws {
        try installer.install()
        #expect(installer.isInstalled)
    }

    @Test func refusesToTouchInvalidSettings() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try Data("{oops".utf8).write(to: installer.settingsURL)
        #expect(throws: HookInstaller.Error.self) { try installer.install() }
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == "{oops")
    }

    @Test func uninstallRestoresCleanSettings() throws {
        try installer.install()
        try installer.uninstall()
        #expect(!installer.isInstalled)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any]
        #expect(json?["hooks"] == nil)
    }

    @Test func unreadableSettingsAreNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try Data(#"{"keep":true}"#.utf8).write(to: installer.settingsURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: installer.settingsURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installer.settingsURL.path) }
        #expect(throws: (any Error).self) { try installer.install() }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installer.settingsURL.path)
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == #"{"keep":true}"#)
    }

    @Test func emptySettingsFileCountsAsEmptyObject() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try Data().write(to: installer.settingsURL)
        try installer.install()
        #expect(installer.isInstalled)
    }

    @Test func keepsSymlinkAndPermissions() throws {
        let fm = FileManager.default
        let real = dir.appendingPathComponent("dotfiles/settings.json")
        try fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: real)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try fm.createSymbolicLink(at: installer.settingsURL, withDestinationURL: real)

        try installer.install()

        #expect(try fm.destinationOfSymbolicLink(atPath: installer.settingsURL.path) == real.path)
        #expect((try fm.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int) == 0o600)
        #expect(installer.isInstalled)
    }

    @Test func noChangeMeansNoWriteAndNoBackup() throws {
        try installer.install()
        let claudeDir = dir.appendingPathComponent("claude").path
        let before = try FileManager.default.contentsOfDirectory(atPath: claudeDir).count
        try installer.install()
        #expect(try FileManager.default.contentsOfDirectory(atPath: claudeDir).count == before)
    }

    @Test func uninstallRemovesScriptToo() throws {
        try installer.install()
        try installer.uninstall()
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    @Test func refreshesOutdatedScriptOnlyWhenInstalled() throws {
        try installer.refreshScriptIfInstalled()
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
        try installer.install()
        try Data("#!/bin/sh\nold\n".utf8).write(to: installer.scriptURL)
        try installer.refreshScriptIfInstalled()
        #expect(try String(contentsOf: installer.scriptURL, encoding: .utf8) == HookInstaller.script)
    }
}

@Suite struct StatusLineSettingsTests {
    let cmd = "'/x/pixelpet-statusline'"

    @Test func installsWhenAbsent() {
        let (out, state) = HookSettings.installStatusLine(into: ["a": 1], command: cmd)
        #expect(state == .ours)
        #expect((out["statusLine"] as? [String: Any])?["command"] as? String == cmd)
        #expect(out["a"] as? Int == 1)
    }

    @Test func leavesForeignStatusLineAlone() {
        let foreign: [String: Any] = ["statusLine": ["type": "command", "command": "my-line"]]
        let (out, state) = HookSettings.installStatusLine(into: foreign, command: cmd)
        #expect(state == .foreign)
        #expect((out["statusLine"] as? [String: Any])?["command"] as? String == "my-line")
    }

    @Test func uninstallRemovesOnlyOurs() {
        let ours = HookSettings.installStatusLine(into: [:], command: cmd).0
        #expect(HookSettings.uninstallStatusLine(from: ours, command: cmd)["statusLine"] == nil)
        let foreign: [String: Any] = ["statusLine": ["type": "command", "command": "my-line"]]
        #expect(HookSettings.uninstallStatusLine(from: foreign, command: cmd)["statusLine"] != nil)
    }
}

@Suite struct StatusLineInstallerTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-sl-\(UUID().uuidString)")
    var installer: HookInstaller {
        HookInstaller(settingsURL: dir.appendingPathComponent("claude/settings.json"),
                      scriptURL: dir.appendingPathComponent("pet/bin/pixelpet-hook"))
    }

    @Test func installAddsStatusLineScriptAndSetting() throws {
        try installer.install()
        #expect(installer.statusLineState == .ours)
        #expect(FileManager.default.isExecutableFile(atPath: installer.statusLineScriptURL.path))
        try installer.uninstall()
        #expect(installer.statusLineState == .absent)
        #expect(!FileManager.default.fileExists(atPath: installer.statusLineScriptURL.path))
    }

    @Test func foreignStatusLineIsReported() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try Data(#"{"statusLine":{"type":"command","command":"mine"}}"#.utf8).write(to: installer.settingsURL)
        try installer.install()
        #expect(installer.statusLineState == .foreign)
        #expect(installer.isInstalled)
    }
}
