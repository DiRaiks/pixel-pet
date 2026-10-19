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
    @ObservationIgnored var onRefreshLimits: (() -> Void)?
}
