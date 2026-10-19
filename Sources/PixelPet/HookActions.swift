import AppKit
import PetCore
import ServiceManagement

/// Connecting and disconnecting Claude Code, shared by the menu, settings and the welcome window.
@MainActor
enum HookActions {
    /// Asks first, then installs; returns true when the pet is connected afterwards.
    @discardableResult
    static func connect(_ hooks: HookInstaller) -> Bool {
        guard confirm() else { return hooks.isInstalled }
        return run { try hooks.install() } && hooks.isInstalled
    }

    static func disconnect(_ hooks: HookInstaller) {
        run { try hooks.uninstall() }
    }

    static func addStatusLine(_ hooks: HookInstaller) {
        run { try hooks.installStatusLine() }
    }

    @discardableResult
    private static func run(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = L("Couldn't change Claude Code settings", "Не получилось изменить настройки Claude Code")
            alert.informativeText = String(describing: error)
            alert.runModal()
            return false
        }
    }

    private static func confirm() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Connect the cube to Claude Code?", "Подключить кубика к Claude Code?")
        alert.informativeText = L("""
        This adds hooks to ~/.claude/settings.json that tell the cube what agents are doing, plus a statusline \
        for terminal sessions (if you don't have your own). The file is backed up next to it first \
        (settings.json.pixelpet-backup-…). It will be reformatted: keys sorted alphabetically, 2-space indent. \
        Prompt text is not stored. You can disconnect from the menu or settings.
        """, """
        В ~/.claude/settings.json добавятся хуки, которые сообщают кубику о работе агентов, и statusline \
        для терминальных сессий (если своей у вас нет). Перед изменением файл копируется рядом \
        (settings.json.pixelpet-backup-…). Файл будет переформатирован: ключи по алфавиту, отступ в 2 пробела. \
        Тексты промптов не сохраняются. Отключить можно в меню или настройках.
        """)
        alert.addButton(withTitle: L("Connect", "Подключить"))
        alert.addButton(withTitle: L("Cancel", "Отмена"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Start at login through the system's login items (System Settings → General → Login Items).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a message to show, or nil when the switch simply worked.
    static func set(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    return L("Allow Pixel Pet in Login Items — the settings window is already open.",
                             "Разрешите Pixel Pet в «Объектах входа» — окно настроек уже открыто.")
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return nil
        } catch {
            return L("That didn't work: \(error.localizedDescription). Launch at login is more reliable from the Applications folder (scripts/install.sh).",
                     "Не получилось: \(error.localizedDescription). Автозапуск надёжнее работает из папки «Программы» (scripts/install.sh).")
        }
    }
}
