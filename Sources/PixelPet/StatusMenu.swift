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
    private let statusLineItem = NSMenuItem(title: "", action: #selector(addStatusLine), keyEquivalent: "")
    private let logItem = NSMenuItem(title: "", action: #selector(toggleLog), keyEquivalent: "")
    private let openLogItem = NSMenuItem(title: "", action: #selector(openLog), keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleHidden), keyEquivalent: "")
    private let limitsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let panelItem = NSMenuItem(title: "", action: #selector(showPanel), keyEquivalent: "")
    private let recapItem = NSMenuItem(title: "", action: #selector(showRecap), keyEquivalent: "")
    private let homeItem = NSMenuItem(title: "", action: #selector(toggleHome), keyEquivalent: "")
    private let dndItem = NSMenuItem(title: "", action: #selector(toggleDND), keyEquivalent: "p")
    private let translateItem = NSMenuItem(title: "", action: #selector(translate), keyEquivalent: "t")
    private let askItem = NSMenuItem(title: "", action: #selector(ask), keyEquivalent: "k")
    private let statesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let scalesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
    private let welcomeItem = NSMenuItem(title: "", action: #selector(openWelcome), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    /// The last limits passed to `update`, so the limits line can be retitled when the language changes.
    private var lastLimits: (claude: UsageLimits?, codex: UsageLimits?) = (nil, nil)
    var onTranslate: (() -> Void)?
    var onSettings: (() -> Void)?
    var onWelcome: (() -> Void)?
    var onAsk: (() -> Void)?
    var onShowPanel: (() -> Void)?
    var onShowRecap: (() -> Void)?
    private let stateMenu = NSMenu()
    private let scaleMenu = NSMenu()

    private static var stateTitles: [PetState: String] {
        [
            .idle: L("Idle", "Покой"), .hop: L("Hop", "Прыжок"), .working: L("Agents working", "Агенты работают"),
            .alert: L("Agent is waiting for input", "Агент ждёт ввода"),
            .celebrate: L("Task done", "Задача готова"), .sleep: L("Sleep", "Сон"), .lowLimit: L("Low limit", "Лимит на исходе"),
            .error: L("Error", "Ошибка"),
            .peek: L("Out of the notch", "Из чёлки"), .burrowed: L("At home (eyes)", "Дома (глаза)"),
            .peekHold: L("Peeking out", "Выглядывает"), .dive: L("Diving home", "Ныряет домой"), .yawn: L("Yawn", "Зевает"),
            .shy: L("Shy", "Смущается"), .angry: L("Angry", "Сердится"), .flip: L("Flip", "Сальто"), .tumble: L("Roll", "Перекат"),
            .drip: L("Drop (LM)", "Капля (LM)"), .melt: L("Puddle (LM)", "Растекается (LM)"), .wave: L("Wave", "Машет"),
            .launch: L("Rocket", "Ракета"), .purr: L("Petted", "Гладят"), .sneeze: L("Sneeze", "Чихает"),
            .headphonesOn: L("Headphones on", "Надевает наушники"), .headphonesOff: L("Headphones off", "Снимает наушники"),
            .music: L("Music", "Музыка"), .onAir: L("On air", "В эфире"), .overheated: L("Overheated", "Перегрелся"),
            .lowPower: L("Low power", "Энергосбережение"), .offline: L("Offline", "Нет сети"),
            .batteryFull: L("Battery full", "Батарея заряжена"), .screenshot: L("Screenshot", "Скриншот"),
            .darkMode: L("Dark mode", "Тёмная тема"), .lightMode: L("Light mode", "Светлая тема"),
            .drop: L("Landing", "Приземление"), .talk: L("Talking", "Отвечает"),
            .workSip: L("Sips coffee", "Пьёт кофе"), .workStretch: L("Stretches", "Потягивается"),
            .workThink: L("Thinking", "Задумался"), .workRush: L("Typing fast", "Строчит"),
            .glanceLeft: L("Looks at Codex", "Смотрит на Codex"), .glanceRight: L("Looks at Claude", "Смотрит на Claude"),
            .touchKey: L("Waits for a key touch", "Ждёт касания ключа"), .touchDone: L("Key touched", "Ключ коснулись"),
            .touchKeyHome: L("Waits for a touch (home)", "Ждёт касания (дома)"),
            .newspaperOpen: L("Opens the newspaper", "Разворачивает газету"), .newspaper: L("Reads the recap", "Читает итоги"),
            .question: L("Agent asks", "Агент спрашивает"), .refill: L("Limit reset", "Лимит обновился"),
            .exhausted: L("Limit spent", "Лимит исчерпан"),
            .spawn: L("Subagents", "Сабагенты"), .recall: L("Subagents back", "Сабагенты вернулись"),
            .compact: L("Compacting context", "Сжимает контекст"),
            .tired: L("Battery low", "Батарея садится"), .plugIn: L("Charging", "Зарядка"), .thrown: L("Thrown", "Кувырок"),
            .dizzy: L("Dizzy", "Кружится голова"),
            .splatLeft: L("Splat on the left edge", "Шлёп о левый край"), .splatRight: L("Splat on the right edge", "Шлёп о правый край"),
            .hookah: L("Hookah", "Кальян"), .hookahCloud: L("Hookah: cloud", "Кальян: облако"),
            .meetingSoon: L("Call soon", "Скоро звонок"), .meetingNow: L("Call now", "Звонок сейчас"),
        ]
    }

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
        recapItem.target = self
        menu.addItem(recapItem)
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

        let states = statesItem
        // `dragged` only makes sense under the cursor, so it isn't offered here.
        for state in PetState.allCases where state != .dragged {
            let entry = NSMenuItem(title: state.rawValue, action: #selector(pickState(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = state.rawValue
            stateMenu.addItem(entry)
        }
        states.submenu = stateMenu
        menu.addItem(states)

        let scales = scalesItem
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
        settingsItem.target = self
        menu.addItem(settingsItem)
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        applyTitles()
    }

    /// Titles in the current language; applied on build and each time the menu opens.
    private func applyTitles() {
        statusLineItem.title = L("Add statusline for the terminal", "Добавить statusline для терминала")
        logItem.title = L("Log events", "Записывать события")
        openLogItem.title = L("Open event log", "Открыть журнал событий")
        panelItem.title = L("Status panel", "Панель статуса")
        recapItem.title = L("Weekly recap…", "Итоги недели…")
        dndItem.title = L("Do not disturb", "Не беспокоить")
        translateItem.title = L("Translate selection", "Перевести выделенное")
        askItem.title = L("Ask Claude", "Спросить Claude")
        statesItem.title = L("State", "Состояние")
        scalesItem.title = L("Size", "Размер")
        settingsItem.title = L("Settings…", "Настройки…")
        welcomeItem.title = L("Welcome…", "Добро пожаловать…")
        quitItem.title = L("Quit Pixel Pet", "Выйти")
        let titles = Self.stateTitles
        for entry in stateMenu.items {
            guard let raw = entry.representedObject as? String, let state = PetState(rawValue: raw) else { continue }
            entry.title = titles[state] ?? raw
        }
        applyLimits()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        applyTitles()
        toggleItem.title = pet.isHidden ? L("Show the cube", "Показать кубика") : L("Hide the cube", "Спрятать кубика")
        homeItem.title = pet.isHome ? L("Let out on the desk", "Выпустить на стол") : L("Send home", "Отправить домой")
        dndItem.state = pet.doNotDisturb ? .on : .off
        hooksItem.title = hooks.isInstalled
            ? L("Disconnect from Claude Code", "Отключить от Claude Code") : L("Connect to Claude Code…", "Подключить к Claude Code…")
        // Connections made before statuslines existed can pick one up here; a user's own statusline is never replaced.
        statusLineItem.isHidden = !(hooks.isInstalled && hooks.statusLineState == .absent)
        // LM's own fidgets are drawn around his diamond; the cube doesn't offer them.
        let lidMan = pet.config.figure == Figure.lidman.rawValue
        for entry in stateMenu.items {
            entry.state = entry.representedObject as? String == pet.restingState.rawValue ? .on : .off
            let raw = entry.representedObject as? String
            entry.isHidden = !lidMan && (raw == PetState.drip.rawValue || raw == PetState.melt.rawValue)
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
        lastLimits = (limits, codexLimits)
        applyLimits()
    }

    private func applyLimits() {
        func parts(_ l: UsageLimits?) -> String? {
            let p = [l?.fiveHour.map { L("5h \(Int($0.usedPercent.rounded()))%", "5 ч \(Int($0.usedPercent.rounded()))%") },
                     l?.sevenDay.map { L("7d \(Int($0.usedPercent.rounded()))%", "7 дн \(Int($0.usedPercent.rounded()))%") }]
                .compactMap { $0 }
            return p.isEmpty ? nil : p.joined(separator: " · ")
        }
        let claude = parts(lastLimits.claude), codex = parts(lastLimits.codex)
        switch (claude, codex) {
        case (nil, nil): limitsItem.title = L("Limits: not known yet", "Лимиты: пока неизвестны")
        case (let c?, nil): limitsItem.title = L("Limits: ", "Лимиты: ") + c
        case (let c, let x?): limitsItem.title = L("Limits: Claude ", "Лимиты: Claude ") + (c ?? "—") + " · Codex " + x
        }
    }

    @objc private func showPanel() { onShowPanel?() }
    @objc private func showRecap() { onShowRecap?() }

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
