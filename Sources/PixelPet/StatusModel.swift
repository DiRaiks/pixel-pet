import Foundation
import Observation
import PetCore

/// What the status panel shows; AgentMonitor keeps it current.
@MainActor
@Observable
final class StatusModel {
    var sessions: [AgentSession] = []
    var limits: UsageLimits?
    var isProbing = false
    var hooksConnected = false
    var now = Date()
    @ObservationIgnored var onRefreshLimits: (() -> Void)?
}
