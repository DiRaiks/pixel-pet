import AppKit
import PetCore
import PetIntegrations

/// Listens for Claude Code hook events and Codex session files, and drives the pet's mood and agent stacks
/// (Claude Code on the right, Codex on the left).
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
    private var lastLaunch = Date.distantPast
    static let launchCooldown: TimeInterval = 60
    private var limits: UsageLimits?
    private var probePolicy = ProbePolicy()
    private var launchProbe: Task<Void, Never>?
    private var server: EventServer?
    private var consumer: Task<Void, Never>?
    private var refreshTimer: Timer?
    /// Codex reports interrupts itself, so quiet turns (a long build) stay "working".
    private var codexRegistry = SessionRegistry(silentWorkTimeout: nil)
    /// Bumped whenever Codex watching starts or stops, so batches from an old watcher are dropped.
    private var codexGeneration = 0
    private var codexLimits: UsageLimits?
    private var codexProbePolicy = ProbePolicy()
    private var codexWatcher: CodexWatcher?
    /// How long the agents have been at it across turns, for the desk props.
    private var workSession = WorkSession()
    /// For noticing changes between refreshes: subagents coming and going, the 5-hour window resetting.
    private var subagentMoments = SubagentMoments()
    private var lastFiveHour: LimitWindow?
    var onChange: ((_ active: Int, _ limits: UsageLimits?, _ codexLimits: UsageLimits?) -> Void)?
    /// A permission request whose hook waits for an answer on the open connection.
    var onPermission: ((Data, HookReply) -> Void)?
    /// A session ended: its waiting requests can't be answered any more.
    var onSessionEnd: ((String) -> Void)?
    /// Each session's last `PreToolUse`: a permission request that follows is about that call.
    private var lastToolUse: [String: (tool: String, id: String)] = [:]
    /// Sessions waiting for a permission, watched in their transcripts: an answer in Claude Code reaches no
    /// hook (a denial that stops the turn least of all), but the call's result is written there at once.
    private var permissionTails: [String: TranscriptTail] = [:]
    /// A request was answered where the session runs; takes the session id.
    var onPermissionAnswered: ((String) -> Void)?

    /// One hook connection: the payload, and the way back for a hook that waits.
    private struct Incoming: @unchecked Sendable {
        let data: Data
        let reply: HookReply?
    }

    init(pet: PetController, hooks: HookInstaller) {
        self.pet = pet
        self.hooks = hooks
        status.onRefreshLimits = { [weak self] in
            self?.probeLimits(.manual)
            self?.probeCodexLimits(.manual)
        }
        limits = pet.config.lastLimits
        codexLimits = pet.config.lastCodexLimits
    }

    func start() {
        let path = Self.socketPath
        // One stream, one consumer: hook events reach the state machine in the order they arrived.
        let (events, continuation) = AsyncStream.makeStream(of: Incoming.self, bufferingPolicy: .bufferingNewest(1000))
        consumer = Task { @MainActor [weak self] in
            for await incoming in events {
                guard let self else {
                    incoming.reply?.send(nil)
                    continue
                }
                if let reply = incoming.reply {
                    if let onPermission { onPermission(incoming.data, reply) } else { reply.send(nil) }
                }
                receive(incoming.data)
            }
        }
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // Also tighten a folder left by an older build; only this user should reach the socket.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
            let server = EventServer(path: path) { data, reply in continuation.yield(Incoming(data: data, reply: reply)) }
            try server.start()
            self.server = server
        } catch {
            NSLog("PixelPet: event server failed to start: \(String(describing: error))")
        }
        setWatchingCodex(pet.config.watchCodex)
        refresh()
        // Learn the limits shortly after launch, once things settle (skipped if the remembered ones are fresh).
        launchProbe = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.probeLimits(.launch)
            self?.probeCodexLimits(.launch)
        }
    }

    /// Settings toggle: follow Codex sessions or forget them.
    func setWatchingCodex(_ on: Bool) {
        guard on != (codexWatcher != nil) else { return }
        codexGeneration += 1
        let generation = codexGeneration
        if on {
            let watcher = CodexWatcher { [weak self] batch in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(batch, generation: generation) } }
            }
            watcher.start()
            codexWatcher = watcher
        } else {
            codexWatcher?.stop()
            codexWatcher = nil
            codexRegistry = SessionRegistry(silentWorkTimeout: nil)
        }
        refresh()
    }

    func stop() {
        permissionTails.values.forEach { $0.stop() }
        permissionTails.removeAll()
        codexWatcher?.stop()
        codexWatcher = nil
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

    private func watchTranscript(for data: Data, session: String) {
        permissionTails.removeValue(forKey: session)?.stop()
        guard let prompt = PermissionPrompt.parse(data), let path = prompt.transcriptPath,
              let useID = prompt.toolUseID ?? lastToolUse[session].flatMap({ $0.tool == prompt.tool ? $0.id : nil })
        else { return }
        var answered = false
        permissionTails[session] = TranscriptTail(path: path) { [weak self] line in
            guard let self, let signal = PermissionPrompt.transcriptSignal(line, toolUseID: useID) else { return }
            if !answered {
                answered = true
                onPermissionAnswered?(session)
            }
            switch signal {
            // Keep watching: a denial's "interrupted" line follows its result.
            case .answered: apply(AgentEvent(sessionID: session, cwd: nil, kind: .permissionSettled))
            case .stopped: permissionSettled(session, stopped: true)
            }
        }
    }

    /// A request was answered where the session runs; `stopped` when that also ended the turn.
    func permissionSettled(_ sessionID: String, stopped: Bool = false) {
        permissionTails.removeValue(forKey: sessionID)?.stop()
        apply(AgentEvent(sessionID: sessionID, cwd: nil, kind: stopped ? .interrupted : .permissionSettled))
    }

    private func apply(_ event: AgentEvent) {
        if pet.config.logEvents { EventLog.append(event.logLine) }
        registry.apply(event, at: Date())
        refresh()
    }

    private func receive(_ data: Data) {
        let now = Date()
        switch Inbound.parse(data, at: now) {
        case .hook(let event):
            switch event.kind {
            case .permissionRequested: watchTranscript(for: data, session: event.sessionID)
            case .notification: break
            default: permissionTails.removeValue(forKey: event.sessionID)?.stop()
            }
            switch event.kind {
            case .sessionEnded:
                lastToolUse[event.sessionID] = nil
                onSessionEnd?(event.sessionID)
            case .toolStarted(let name, let useID?): lastToolUse[event.sessionID] = (name, useID)
            default: break
            }
            if pet.config.logEvents { EventLog.append(event.logLine) }
            // A successful `git push`: a rocket, at most once a minute.
            if event.pushed, now.timeIntervalSince(lastLaunch) >= Self.launchCooldown, pet.moment(.launch) {
                lastLaunch = now
            }
            switch registry.apply(event, at: now) {
            case .finished: pet.react(.celebrate)
            case .finishedBig:
                if pet.react(.flip) { pet.maybeHookahBreak() }
            case .compacted: pet.moment(.compact)
            case .failed, nil: break
            }
        case .statusline(let snapshot):
            if pet.config.logEvents { EventLog.append(snapshot.logLine) }
            registry.apply(snapshot, at: now)
            if let observed = snapshot.limits { merge(observed) }
        case nil:
            return
        }
        refresh()
    }

    /// Codex lines, in the order they were written. Catch-up batches update the picture without reactions.
    private func receive(_ batch: CodexWatcher.Batch, generation: Int) {
        guard codexWatcher != nil, generation == codexGeneration else { return }
        let now = Date()
        for output in batch.outputs {
            switch output {
            case .event(let event, let at):
                // "Still working" comes with nearly every line; it would flood the log.
                if pet.config.logEvents, event.kind != .stillWorking { EventLog.append("codex " + event.logLine) }
                let reaction = codexRegistry.apply(event, at: at)
                // Only what just happened earns a reaction, not turns found in a file read late.
                guard !batch.isReplay, CodexRollout.isLive(at, now: now) else { continue }
                switch reaction {
                case .finished: pet.react(.celebrate)
                case .finishedBig:
                    if pet.react(.flip) { pet.maybeHookahBreak() }
                case .compacted: pet.moment(.compact)
                case .failed, nil: break
                }
            case .limits(let observed):
                mergeCodex(observed)
            }
        }
        refresh(noticing: !batch.isReplay)
    }

    private func mergeCodex(_ observed: UsageLimits) {
        codexLimits = codexLimits.map { $0.merged(with: observed) } ?? observed
        pet.rememberCodexLimits(codexLimits)
    }

    /// Codex limits from a short `codex app-server` call: no model request, so it costs nothing.
    func probeCodexLimits(_ reason: ProbePolicy.Reason) {
        let now = Date()
        guard codexWatcher != nil,
              codexProbePolicy.allows(reason, now: now, limitsObservedAt: codexLimits?.observedAt) else { return }
        codexProbePolicy.started(at: now)
        guard let codex = CodexLocator.find() else {
            codexProbePolicy.finished(success: false)
            return
        }
        Task { @MainActor [weak self] in
            let observed = await CodexLimitsProbe.run(codex: codex)
            guard let self else { return }
            codexProbePolicy.finished(success: observed != nil)
            // Codex may have been switched off meanwhile.
            if let observed, codexWatcher != nil { mergeCodex(observed) }
            refresh()
        }
    }

    /// Subagents starting (copies pop out) or all finished (they come back), and the 5-hour window
    /// resetting after real use (the pet fills back up).
    private func noticeMoments(sessions: [AgentSession], fiveHour: LimitWindow?, now: Date) {
        if let moment = subagentMoments.update(count: PetBrain.subagentCount(sessions), now: now) { pet.moment(moment) }
        if UsageLimits.refilled(before: lastFiveHour, after: fiveHour) { pet.moment(.refill) }
    }

    /// Limits seen elsewhere (e.g. a Claude translation run).
    func absorb(_ observed: UsageLimits) {
        merge(observed)
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

    /// `noticing: false` for catch-up: blocks may change, but the pet doesn't look over at history.
    private func refresh(noticing: Bool = true) {
        let now = Date()
        registry.prune(now: now)
        codexRegistry.prune(now: now)
        let sessions = registry.ordered
        let codex = codexRegistry.ordered
        let current = limits?.current(at: now)
        // The mood follows every agent; the drained body and the low-limit look stay Claude's.
        pet.setMood(PetBrain.baseState(for: sessions + codex, limits: limits, now: now))
        pet.setAgents(PetBrain.cubes(for: sessions, now: now), codex: PetBrain.cubes(for: codex, now: now),
                      noticing: noticing)
        pet.setDrain(current?.drainRows(interior: Self.drainInterior) ?? 0)
        // Desk props grow over the whole stretch of work, across turns and short pauses.
        workSession.update(working: (sessions + codex).contains { $0.status == .working }, now: now)
        pet.setWorkStage(WorkStage.stage(worked: workSession.worked(now: now)))
        pet.setTool(ToolKind.current(in: sessions))
        pet.setWaitingSince((sessions + codex).filter { $0.status == .waiting }.compactMap(\.waitingSince).min())
        let active = PetBrain.activeCount(sessions + codex)
        onChange?(active, current, codexWatcher == nil ? nil : codexLimits?.current(at: now))
        status.sessions = sessions
        status.limits = limits
        if noticing {
            noticeMoments(sessions: sessions + codex, fiveHour: current?.fiveHour, now: now)
        } else {
            subagentMoments.prime(count: PetBrain.subagentCount(sessions + codex))
        }
        lastFiveHour = current?.fiveHour
        status.codexSessions = codex
        status.codexLimits = codexLimits
        status.codexEnabled = codexWatcher != nil
        status.hooksConnected = hooks.isInstalled
        status.now = now
        if PetBrain.activeCount(sessions) > 0 { probeLimits(.busy) }
        scheduleRefresh(sessions + codex, now, extra: workSession.nextChange(now: now))
    }

    /// Called when the panel opens: refresh the picture, and the limits if they're older than a few minutes.
    func panelWillShow() {
        refresh()
        probeLimits(.panel)
        probeCodexLimits(.panel)
    }

    /// Wakes up only when something changes without an event: a flash or error window ends,
    /// an interrupted session settles, or a session goes stale.
    private func scheduleRefresh(_ sessions: [AgentSession], _ now: Date, extra: Date? = nil) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let visual = [PetBrain.nextChange(for: sessions, now: now), extra].compactMap { $0 }.min()
        let resets = limits?.nextReset(after: now)
        let codexResets = codexLimits?.nextReset(after: now)
        let housekeeping = [registry.nextExpiry(), codexRegistry.nextExpiry(), resets, codexResets].compactMap { $0 }.min().map { max($0, now.addingTimeInterval(1)) }
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
