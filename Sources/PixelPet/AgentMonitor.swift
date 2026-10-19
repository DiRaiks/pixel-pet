import AppKit
import PetCore
import PetIntegrations

/// Listens for Claude Code hook events and drives the pet's mood and agent stack.
@MainActor
final class AgentMonitor {
    static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelpet/pet.sock").path
    }

    private let pet: PetController
    private var registry = SessionRegistry()
    private var server: EventServer?
    private var consumer: Task<Void, Never>?
    private var refreshTimer: Timer?
    var onChange: ((_ active: Int) -> Void)?

    init(pet: PetController) {
        self.pet = pet
    }

    func start() {
        let path = Self.socketPath
        // One stream, one consumer: hook events reach the state machine in the order they arrived.
        let (events, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(1000))
        consumer = Task { @MainActor [weak self] in
            for await data in events { self?.receive(data) }
        }
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // Also tighten a folder left by an older build; only this user should reach the socket.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
            let server = EventServer(path: path) { continuation.yield($0) }
            try server.start()
            self.server = server
        } catch {
            NSLog("PixelPet: event server failed to start: \(String(describing: error))")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        consumer?.cancel()
        consumer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    var sessions: [AgentSession] { registry.ordered }

    private func receive(_ data: Data) {
        guard let event = AgentEvent.parse(data) else { return }
        let reaction = registry.apply(event, at: Date())
        switch reaction {
        case .finished: pet.react(.celebrate)
        case .failed, nil: break
        }
        refresh()
    }

    private func refresh() {
        let now = Date()
        registry.prune(now: now)
        let sessions = registry.ordered
        pet.setMood(PetBrain.baseState(for: sessions, now: now))
        pet.setAgents(PetBrain.cubes(for: sessions, now: now))
        onChange?(PetBrain.activeCount(sessions))
        scheduleRefresh(sessions, now)
    }

    /// Wakes up only when something changes without an event: a flash or error window ends,
    /// an interrupted session settles, or a session goes stale.
    private func scheduleRefresh(_ sessions: [AgentSession], _ now: Date) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let visual = PetBrain.nextChange(for: sessions, now: now)
        let housekeeping = registry.nextExpiry().map { max($0, now.addingTimeInterval(1)) }
        guard let next = [visual, housekeeping].compactMap({ $0 }).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Visual changes should land on time; housekeeping can drift a few seconds to save wake-ups.
        timer.tolerance = next == visual ? 0.1 : 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }
}
