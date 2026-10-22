import Foundation
@testable import PetIntegrations
import Testing

struct ClaudeWorkdirTests {
    /// Matches the folder names Claude Code writes, seen in ~/.claude/projects.
    @Test func folderNamesFollowClaudeCode() {
        #expect(ClaudeWorkdir.projectFolderName(forPath: "/private/var/folders/nf/lbs_9yvd1ml__5jh3z9x3yhr0000gn/T/pixelpet-claude")
                == "-private-var-folders-nf-lbs-9yvd1ml--5jh3z9x3yhr0000gn-T-pixelpet-claude")
        #expect(ClaudeWorkdir.projectFolderName(forPath: "/Users/a/Work/Lido/") == "-Users-a-Work-Lido")
        #expect(ClaudeWorkdir.projectFolderName(forPath: "/Users/a/Проект") == "-Users-a-------")
    }

    /// A project of yours whose folder only ends like the pet's is never among the names to remove.
    @Test func onlyThePetsOwnFolders() {
        let names = ClaudeWorkdir.sessionFolderNames
        #expect(names.count <= 4)
        #expect(names.allSatisfy { $0.hasSuffix("-pixelpet-claude") || $0.hasSuffix("-pixelpet-probe") })
        #expect(!names.contains("-Users-a-Work-pixelpet-claude"))
        #expect(names.contains(ClaudeWorkdir.projectFolderName(forPath: ClaudeWorkdir.url.path)))
    }
}
