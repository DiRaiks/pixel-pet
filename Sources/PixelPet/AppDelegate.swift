import AppKit
import Carbon
import PetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var agents: AgentMonitor?
    private var menu: StatusMenu?
    private var panel: StatusPanel?
    private var hotKeys: [HotKey] = []
    private var translator: Translator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One pet at a time: a second copy would fight over the socket and the screen.
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: me.bundleIdentifier ?? "")
            .contains(where: { $0 != me && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        let hooks = HookInstaller()
        do {
            try hooks.refreshScriptIfInstalled()
        } catch {
            NSLog("PixelPet: failed to refresh hook script: \(error.localizedDescription)")
        }
        let pet = PetController(store: ConfigStore(), sprites: SpriteLibrary())
        let agents = AgentMonitor(pet: pet, hooks: hooks)
        let panel = StatusPanel(model: agents.status)
        let menu = StatusMenu(pet: pet, hooks: hooks)
        agents.onChange = { [weak menu] active, limits in
            menu?.update(active: active, limits: limits)
            DispatchQueue.main.async { panel.refit() }
        }
        let showPanel = { [weak agents, weak pet] in
            guard let agents, let pet, !pet.isHidden else { return }
            if !panel.isShown { agents.panelWillShow() }
            panel.toggle(from: pet.anchorView)
        }
        pet.onTap = showPanel

        menu.onShowPanel = showPanel
        self.panel = panel
        let translator = Translator(pet: pet)
        translator.onLimits = { [weak agents] in agents?.absorb($0) }
        self.translator = translator
        // Only one card at a time.
        translator.panel.onShow = { [weak panel] in panel?.close() }
        let statusShow = panel.onShow
        panel.onShow = { [weak translator] in
            translator?.panel.close()
            statusShow?()
        }
        menu.onTranslate = { [weak translator] in translator?.translateSelection() }
        pet.onDragStart = { [weak translator] in
            panel.close()
            translator?.panel.close()
        }
        // ⌃⌥P: do not disturb (home, quiet). ⌃⌥T: translate the selection. Shown next to the menu items too.
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { [weak menu] in menu?.toggleDND() },
            HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey, id: 2) { [weak translator] in
                translator?.translateSelection()
            },
        ]
        // Debug aid: `open PixelPet.app --args --show-panel` opens the panel once limits had time to load.
        if let i = CommandLine.arguments.firstIndex(of: "--translate-text"), i + 1 < CommandLine.arguments.count {
            let text = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { translator.translate(text) }
            if CommandLine.arguments.contains("--with-claude") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { translator.translateWithClaude() }
            }
        }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { showPanel() }
        }
        pet.contextMenu = menu.menu
        self.pet = pet
        self.agents = agents
        self.menu = menu
        pet.start()
        agents.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        agents?.stop()
    }
}
