import Foundation
import Observation
import PetCore

/// What the status panel shows; AgentMonitor keeps it current.
@MainActor
@Observable
final class StatusModel {
    var sessions: [AgentSession] = []
    var limits: UsageLimits?
    var codexSessions: [AgentSession] = []
    var codexLimits: UsageLimits?
    /// Codex is followed (setting on): its limits and sessions get their own groups.
    var codexEnabled = false
    /// The next call within the hour, when calendar reminders are on.
    var nextMeeting: Meeting?
    var isProbing = false
    var hooksConnected = false
    var now = Date()
    /// Work without a break so far, when the reminder is near (nil otherwise).
    @ObservationIgnored var breakWorked: ((Date) -> TimeInterval?)?
    @ObservationIgnored var onRefreshLimits: (() -> Void)?
}
