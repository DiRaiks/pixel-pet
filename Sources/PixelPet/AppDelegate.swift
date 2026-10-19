import AppKit
import PetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetController?
    private var agents: AgentMonitor?
    private var menu: StatusMenu?
    private var panel: StatusPanel?

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
        pet.onDragStart = { panel.close() }
        menu.onShowPanel = showPanel
        self.panel = panel
        // Debug aid: `open PixelPet.app --args --show-panel` opens the panel once limits had time to load.
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
