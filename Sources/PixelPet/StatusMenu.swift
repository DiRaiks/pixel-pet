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
    private let translateItem = NSMenuItem(title: "Перевести выделенное", action: #selector(translate), keyEquivalent: "t")
    private let askItem = NSMenuItem(title: "Спросить Claude", action: #selector(ask), keyEquivalent: "k")
    var onTranslate: (() -> Void)?
    var onSettings: (() -> Void)?
    var onWelcome: (() -> Void)?
    var onAsk: (() -> Void)?
    var onShowPanel: (() -> Void)?
    private let stateMenu = NSMenu()
    private let scaleMenu = NSMenu()

    private static let stateTitles: [PetState: String] = [
        .idle: "Покой", .hop: "Прыжок", .working: "Агенты работают", .alert: "Агент ждёт ввода",
        .celebrate: "Задача готова", .sleep: "Сон", .lowLimit: "Лимит на исходе", .error: "Ошибка",
        .peek: "Из чёлки", .burrowed: "Дома (глаза)", .peekHold: "Выглядывает", .dive: "Ныряет домой", .yawn: "Зевает", .shy: "Смущается", .angry: "Сердится", .flip: "Сальто", .tumble: "Перекат", .drop: "Приземление", .talk: "Отвечает",
        .workSip: "Пьёт кофе", .workStretch: "Потягивается", .workThink: "Задумался", .workRush: "Строчит",
        .glanceLeft: "Смотрит на Codex", .glanceRight: "Смотрит на Claude",
        .touchKey: "Ждёт касания ключа", .touchDone: "Ключ коснулись", .touchKeyHome: "Ждёт касания (дома)",
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
        translateItem.target = self
        translateItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(translateItem)
        askItem.target = self
        askItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(askItem)
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
        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let welcome = NSMenuItem(title: "Добро пожаловать…", action: #selector(openWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
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
    func update(active: Int, limits: UsageLimits?, codexLimits: UsageLimits? = nil) {
        item.button?.title = active > 0 ? " \(active)" : ""
        func parts(_ l: UsageLimits?) -> String? {
            let p = [l?.fiveHour.map { "5 ч \(Int($0.usedPercent.rounded()))%" },
                     l?.sevenDay.map { "7 дн \(Int($0.usedPercent.rounded()))%" }].compactMap { $0 }
            return p.isEmpty ? nil : p.joined(separator: " · ")
        }
        let claude = parts(limits), codex = parts(codexLimits)
        switch (claude, codex) {
        case (nil, nil): limitsItem.title = "Лимиты: пока неизвестны"
        case (let c?, nil): limitsItem.title = "Лимиты: " + c
        case (let c, let x?): limitsItem.title = "Лимиты: Claude " + (c ?? "—") + " · Codex " + x
        }
    }

    @objc private func showPanel() { onShowPanel?() }

    @objc private func toggleHome() { pet.toggleHome() }

    @objc private func translate() { onTranslate?() }

    @objc private func ask() { onAsk?() }

    @objc func toggleDND() { pet.setDoNotDisturb(!pet.doNotDisturb) }

    @objc private func toggleHooks() {
        if hooks.isInstalled {
            HookActions.disconnect(hooks)
        } else {
            HookActions.connect(hooks)
        }
    }

    @objc private func addStatusLine() { HookActions.addStatusLine(hooks) }

    @objc private func openSettings() { onSettings?() }

    @objc private func openWelcome() { onWelcome?() }

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
