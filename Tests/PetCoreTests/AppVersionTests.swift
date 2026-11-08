import Foundation
import Testing
@testable import PetCore

@Suite struct AppVersionTests {
    @Test func acceptsReleaseVersionsOnly() {
        for v in ["0.3.0", "1.10", "0.3.0-beta.1", "2"] { #expect(AppVersion.isValid(v), "\(v)") }
        for v in ["", "v0.3.0", "0.3.0 ", "../x", "0.3</string>", "1..2", "0.3-"] { #expect(!AppVersion.isValid(v), "\(v)") }
    }

    /// By the numbers, not the text: 0.10 is newer than 0.9; a suffix doesn't count; junk is never newer.
    @Test func comparesByTheNumbers() {
        #expect(AppVersion.isNewer("0.2.2", than: "0.2.1"))
        #expect(AppVersion.isNewer("0.10.0", than: "0.9.9"))
        #expect(AppVersion.isNewer("1.0", than: "0.99.99"))
        #expect(!AppVersion.isNewer("0.2.1", than: "0.2.1"))
        #expect(!AppVersion.isNewer("0.2.1", than: "0.2.2"))
        #expect(!AppVersion.isNewer("0.3.0", than: "0.3.0-beta.1"))
        #expect(!AppVersion.isNewer("0.3", than: "0.3.0"))
        #expect(!AppVersion.isNewer("junk", than: "0.1.0"))
    }

    @Test func linksToTheReleasePage() {
        #expect(AppVersion.releasePage("0.3.0")?.absoluteString == "https://github.com/DiRaiks/pixel-pet/releases/tag/v0.3.0")
        #expect(AppVersion.releasePage("../../x") == nil)
    }

    /// The last version that ran and the update check setting survive the config, and an old config has
    /// checks on and no last version.
    @Test func configKeepsTheLastVersionAndTheCheckSetting() throws {
        let old = try JSONSerialization.data(withJSONObject: ["touchHint": true])
        let decoded = try JSONDecoder().decode(PetConfig.self, from: old)
        #expect(decoded.checkUpdates)
        #expect(decoded.lastVersion == nil)
        var config = PetConfig()
        config.lastVersion = "0.3.0"
        config.checkUpdates = false
        let back = try JSONDecoder().decode(PetConfig.self, from: JSONEncoder().encode(config))
        #expect(back.lastVersion == "0.3.0" && !back.checkUpdates)
    }
}
