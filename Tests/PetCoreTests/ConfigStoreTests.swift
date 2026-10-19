import Foundation
import Testing
@testable import PetCore

@Suite struct ConfigStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-tests-\(UUID().uuidString)")
    var url: URL { dir.appendingPathComponent("nested/config.json") }

    @Test func missingFileGivesDefaults() {
        #expect(ConfigStore(url: url).load() == PetConfig())
    }

    @Test func roundTripsAndCreatesDirectories() throws {
        let store = ConfigStore(url: url)
        var config = PetConfig()
        config.origin = PetPoint(x: 120, y: 340)
        config.scale = 5
        config.isHidden = true
        try store.save(config)
        #expect(store.load() == config)
    }

    @Test func corruptFileGivesDefaults() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        #expect(ConfigStore(url: url).load() == PetConfig())
    }

    @Test func unknownAndMissingKeysAreTolerated() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"scale":3,"future":"x"}"#.utf8).write(to: url)
        let config = ConfigStore(url: url).load()
        #expect(config.scale == 3)
        #expect(config.origin == nil)
        #expect(config.isHidden == false)
    }

    /// The interface is English unless Russian was chosen; older configs without the key get English.
    @Test func interfaceLanguageDefaultsToEnglish() throws {
        #expect(PetConfig().uiLanguage == "en")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"scale":3}"#.utf8).write(to: url)
        #expect(ConfigStore(url: url).load().uiLanguage == "en")
        var config = PetConfig()
        config.uiLanguage = "ru"
        try ConfigStore(url: url).save(config)
        #expect(ConfigStore(url: url).load().uiLanguage == "ru")
    }

    @Test func figureDefaultsToTheCubeAndRoundTrips() throws {
        #expect(PetConfig().figure == "cube")
        let store = ConfigStore(url: url)
        var config = PetConfig()
        config.figure = "lidman"
        try store.save(config)
        #expect(store.load().figure == "lidman")
    }

    @Test func scaleIsClampedToSupportedRange() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"scale":40}"#.utf8).write(to: url)
        #expect(ConfigStore(url: url).load().scale == PetConfig.scaleRange.upperBound)
    }
}

@Suite struct ConfigStoreBackupTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-tests-\(UUID().uuidString)")

    @Test func corruptFileIsKeptAsBackup() throws {
        let url = dir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: url)
        _ = ConfigStore(url: url).load()
        let backup = try String(contentsOf: url.appendingPathExtension("bak"), encoding: .utf8)
        #expect(backup == "{broken")
    }
}
