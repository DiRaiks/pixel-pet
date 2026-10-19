import AppKit
import PetCore
import PetIntegrations

/// Listens for Claude Code hook events and drives the pet's mood and agent stack.
@MainActor
final class AgentMonitor {
    static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelpet/pet.sock").path
    }

    /// Rows of body interior the 5-hour limit can drain.
    static let drainInterior = 12

    private let pet: PetController
    private let hooks: HookInstaller
    let status = StatusModel()
    private var registry = SessionRegistry()
    private var limits: UsageLimits?
    private var probePolicy = ProbePolicy()
    private var launchProbe: Task<Void, Never>?
    private var server: EventServer?
    private var consumer: Task<Void, Never>?
    private var refreshTimer: Timer?
    var onChange: ((_ active: Int, _ limits: UsageLimits?) -> Void)?

    init(pet: PetController, hooks: HookInstaller) {
        self.pet = pet
        self.hooks = hooks
        status.onRefreshLimits = { [weak self] in self?.probeLimits(.manual) }
        limits = pet.config.lastLimits
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
        refresh()
        // Learn the limits shortly after launch, once things settle (skipped if the remembered ones are fresh).
        launchProbe = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.probeLimits(.launch)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        consumer?.cancel()
        consumer = nil
        launchProbe?.cancel()
        launchProbe = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    var sessions: [AgentSession] { registry.ordered }

    private func receive(_ data: Data) {
        let now = Date()
        switch Inbound.parse(data, at: now) {
        case .hook(let event):
            if pet.config.logEvents { EventLog.append(event.logLine) }
            if registry.apply(event, at: now) == .finished { pet.react(.celebrate) }
        case .statusline(let snapshot):
            if pet.config.logEvents { EventLog.append(snapshot.logLine) }
            registry.apply(snapshot, at: now)
            if let observed = snapshot.limits { merge(observed) }
        case nil:
            return
        }
        refresh()
    }

    private func merge(_ observed: UsageLimits) {
        limits = limits.map { $0.merged(with: observed) } ?? observed
        pet.rememberLimits(limits)
    }

    /// Runs the cheap `claude -p` probe for fresh limits when the policy allows it (one at a time,
    /// cooldown after success, growing backoff after failures).
    func probeLimits(_ reason: ProbePolicy.Reason) {
        let now = Date()
        guard probePolicy.allows(reason, now: now, limitsObservedAt: limits?.observedAt) else { return }
        probePolicy.started(at: now)
        guard let claude = ClaudeLocator.find() else {
            probePolicy.finished(success: false)
            return
        }
        status.isProbing = true
        Task { @MainActor [weak self] in
            let observed = await LimitsProbe.run(claude: claude)
            guard let self else { return }
            probePolicy.finished(success: observed != nil)
            status.isProbing = false
            if let observed { merge(observed) }
            refresh()
        }
    }

    private func refresh() {
        let now = Date()
        registry.prune(now: now)
        let sessions = registry.ordered
        let current = limits?.current(at: now)
        pet.setMood(PetBrain.baseState(for: sessions, limits: limits, now: now))
        pet.setAgents(PetBrain.cubes(for: sessions, now: now))
        pet.setDrain(current?.drainRows(interior: Self.drainInterior) ?? 0)
        let active = PetBrain.activeCount(sessions)
        onChange?(active, current)
        status.sessions = sessions
        status.limits = limits
        status.hooksConnected = hooks.isInstalled
        status.now = now
        if active > 0 { probeLimits(.busy) }
        scheduleRefresh(sessions, now)
    }

    /// Called when the panel opens: refresh the picture, and the limits if they're older than a few minutes.
    func panelWillShow() {
        refresh()
        probeLimits(.panel)
    }

    /// Wakes up only when something changes without an event: a flash or error window ends,
    /// an interrupted session settles, or a session goes stale.
    private func scheduleRefresh(_ sessions: [AgentSession], _ now: Date) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let visual = PetBrain.nextChange(for: sessions, now: now)
        let resets = limits?.nextReset(after: now)
        let housekeeping = [registry.nextExpiry(), resets].compactMap { $0 }.min().map { max($0, now.addingTimeInterval(1)) }
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

/// Opt-in plain-text log for debugging what the hooks report. Rotates at 1 MB, keeping one old file.
enum EventLog {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pixelpet/events.log")
    }
    static let maxSize = 1 << 20
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func append(_ line: String) {
        let fm = FileManager.default
        if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxSize {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        let data = Data("\(stamp.string(from: Date())) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
