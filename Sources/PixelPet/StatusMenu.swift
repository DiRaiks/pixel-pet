import AppKit
import PetCore
import PetSprites

/// Menu-bar item with a mini cube; the same menu doubles as the pet's right-click menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pet: PetController
    private let hooks: HookInstaller
    private let hooksItem = NSMenuItem(title: "", action: #selector(toggleHooks), keyEquivalent: "")
    private let statusLineItem = NSMenuItem(title: "Добавить statusline для терминала", action: #selector(addStatusLine),
                                            keyEquivalent: "")
    private let logItem = NSMenuItem(title: "Записывать события", action: #selector(toggleLog), keyEquivalent: "")
    private let openLogItem = NSMenuItem(title: "Открыть журнал событий", action: #selector(openLog), keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleHidden), keyEquivalent: "")
    private let limitsItem = NSMenuItem(title: "Лимиты: пока неизвестны", action: nil, keyEquivalent: "")
    private let panelItem = NSMenuItem(title: "Панель статуса", action: #selector(showPanel), keyEquivalent: "")
    private let homeItem = NSMenuItem(title: "", action: #selector(toggleHome), keyEquivalent: "")
    private let dndItem = NSMenuItem(title: "Не беспокоить", action: #selector(toggleDND), keyEquivalent: "p")
    var onShowPanel: (() -> Void)?
    private let stateMenu = NSMenu()
    private let scaleMenu = NSMenu()

    private static let stateTitles: [PetState: String] = [
        .idle: "Покой", .hop: "Прыжок", .working: "Агенты работают", .alert: "Агент ждёт ввода",
        .celebrate: "Задача готова", .sleep: "Сон", .lowLimit: "Лимит на исходе", .error: "Ошибка",
        .peek: "Из чёлки", .burrowed: "Дома (глаза)", .peekHold: "Выглядывает", .dive: "Ныряет домой", .drop: "Приземление", .talk: "Отвечает",
    ]

    init(pet: PetController, hooks: HookInstaller) {
        self.pet = pet
        self.hooks = hooks
        super.init()
        item.button?.image = Self.icon()
        item.button?.toolTip = "Pixel Pet"
        item.button?.imagePosition = .imageLeading
        item.length = NSStatusItem.variableLength
        item.menu = menu
        menu.delegate = self
        build()
    }

    private func build() {
        limitsItem.isEnabled = false
        menu.addItem(limitsItem)
        panelItem.target = self
        menu.addItem(panelItem)
        homeItem.target = self
        menu.addItem(homeItem)
        dndItem.target = self
        dndItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(dndItem)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        hooksItem.target = self
        menu.addItem(hooksItem)
        statusLineItem.target = self
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        let states = NSMenuItem(title: "Состояние", action: nil, keyEquivalent: "")
        // `dragged` only makes sense under the cursor, so it isn't offered here.
        for state in PetState.allCases where state != .dragged {
            let entry = NSMenuItem(title: Self.stateTitles[state] ?? state.rawValue, action: #selector(pickState(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = state.rawValue
            stateMenu.addItem(entry)
        }
        states.submenu = stateMenu
        menu.addItem(states)

        let scales = NSMenuItem(title: "Размер", action: nil, keyEquivalent: "")
        for scale in PetConfig.scaleRange {
            let entry = NSMenuItem(title: "×\(scale)", action: #selector(pickScale(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = scale
            scaleMenu.addItem(entry)
        }
        scales.submenu = scaleMenu
        menu.addItem(scales)

        logItem.target = self
        openLogItem.target = self
        menu.addItem(.separator())
        menu.addItem(logItem)
        menu.addItem(openLogItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = pet.isHidden ? "Показать кубика" : "Спрятать кубика"
        homeItem.title = pet.isHome ? "Выпустить на стол" : "Отправить домой"
        dndItem.state = pet.doNotDisturb ? .on : .off
        hooksItem.title = hooks.isInstalled ? "Отключить от Claude Code" : "Подключить к Claude Code…"
        // Connections made before statuslines existed can pick one up here; a user's own statusline is never replaced.
        statusLineItem.isHidden = !(hooks.isInstalled && hooks.statusLineState == .absent)
        for entry in stateMenu.items {
            entry.state = entry.representedObject as? String == pet.restingState.rawValue ? .on : .off
        }
        logItem.state = pet.config.logEvents ? .on : .off
        openLogItem.isHidden = !FileManager.default.fileExists(atPath: EventLog.url.path)
        for entry in scaleMenu.items {
            entry.state = entry.tag == pet.config.scale ? .on : .off
        }
    }

    @objc private func toggleHidden() { pet.setHidden(!pet.isHidden) }

    @objc private func toggleLog() { pet.setLogEvents(!pet.config.logEvents) }

    @objc private func openLog() { NSWorkspace.shared.open(EventLog.url) }

    /// Count of working or waiting agents next to the icon (nothing when all is quiet) and the limits line.
    func update(active: Int, limits: UsageLimits?) {
        item.button?.title = active > 0 ? " \(active)" : ""
        let parts = [limits?.fiveHour.map { "5 ч \(Int($0.usedPercent.rounded()))%" },
                     limits?.sevenDay.map { "7 дн \(Int($0.usedPercent.rounded()))%" }].compactMap { $0 }
        limitsItem.title = parts.isEmpty ? "Лимиты: пока неизвестны" : "Лимиты: " + parts.joined(separator: " · ")
    }

    @objc private func showPanel() { onShowPanel?() }

    @objc private func toggleHome() { pet.toggleHome() }

    @objc func toggleDND() { pet.setDoNotDisturb(!pet.doNotDisturb) }

    @objc private func toggleHooks() {
        do {
            if hooks.isInstalled {
                try hooks.uninstall()
            } else if confirmInstall() {
                try hooks.install()
            }
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Не получилось изменить настройки Claude Code"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }

    @objc private func addStatusLine() {
        do {
            try hooks.installStatusLine()
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Не получилось изменить настройки Claude Code"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }

    private func confirmInstall() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Подключить кубика к Claude Code?"
        alert.informativeText = """
        В ~/.claude/settings.json добавятся хуки, которые сообщают кубику о работе агентов. \
        Перед изменением файл копируется рядом (settings.json.pixelpet-backup-…). \
        Файл будет переформатирован: ключи по алфавиту, отступ в 2 пробела. \
        Тексты промптов не сохраняются. Отключить можно в этом же меню.
        """
        alert.addButton(withTitle: "Подключить")
        alert.addButton(withTitle: "Отмена")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func pickState(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let state = PetState(rawValue: raw) else { return }
        if pet.isHidden { pet.setHidden(false) }
        pet.preview(state)
    }

    @objc private func pickScale(_ sender: NSMenuItem) { pet.setScale(sender.tag) }

    /// Template silhouette so macOS tints it correctly on light and dark menu bars.
    private static func icon() -> NSImage? {
        guard let cube = SpriteFactory.menuIcon().makeImage() else { return nil }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.cgContext.draw(cube, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
