import Foundation
import PetCore

/// Keeps `AgentStats` for the weekly recap: records as things happen, writes the file at most once a
/// minute (and on quit). Records nothing while the recap is off.
@MainActor
final class StatsKeeper {
    private let store: StatsStore
    private(set) var stats: AgentStats
    private var dirty = false
    private var timer: Timer?
    var enabled: Bool

    init(store: StatsStore = StatsStore(), enabled: Bool) {
        self.store = store
        self.enabled = enabled
        stats = store.load()
        stats.prune(now: Date())
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func record(_ change: (inout AgentStats) -> Void) {
        guard enabled else { return }
        change(&stats)
        dirty = true
    }

    func save() {
        guard dirty else { return }
        dirty = false
        stats.prune(now: Date())
        do {
            try store.save(stats)
        } catch {
            NSLog("PixelPet: failed to save stats: \(error.localizedDescription)")
        }
    }

    /// "Clear statistics": the file goes, and counting starts over.
    func clear() {
        stats = AgentStats()
        dirty = false
        store.remove()
    }

    func stop() {
        save()
        timer?.invalidate()
        timer = nil
    }
}
