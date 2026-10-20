import Foundation

/// What a system notification says about a session. Only the project and what happened: Notification Center
/// keeps a history, so commands, files and questions stay out.
public enum AgentNotice: Equatable, Sendable {
    case permission
    case question
    case finished(took: TimeInterval?, steps: Int)
    case failed
}

public enum NotificationMode: String, Codable, CaseIterable, Sendable {
    case off
    /// Only while the pet can't be seen (hidden, covered, behind a fullscreen app).
    case whenHidden
    case always
}

/// When a session's change posts, replaces or clears its notification (one per session).
public enum NoticePlan {
    public enum Action: Equatable, Sendable {
        case post(AgentNotice)
        case clear
    }

    /// From the session before and after an event (nil: not there), and the registry's reaction to it.
    public static func action(before: AgentSession?, after: AgentSession?, reaction: AgentReaction?) -> Action? {
        guard let after else { return before == nil ? nil : .clear }
        switch reaction {
        case .finished, .finishedBig: return .post(.finished(took: after.lastTurn, steps: after.lastSteps))
        case .failed: return .post(.failed)
        case .compacted, nil: break
        }
        if after.status == .waiting, before?.status != .waiting || before?.waitingFor != after.waitingFor {
            return .post(after.waitingFor == .permission ? .permission : .question)
        }
        // Answered, or a new turn: what the notification asked about is over.
        if after.status == .working, before?.status != .working { return .clear }
        if before?.status == .waiting, after.status != .waiting { return .clear }
        return nil
    }

    /// Clearing always goes through; posting only when the mode allows it and the pet isn't told to keep quiet.
    public static func posts(mode: NotificationMode, petVisible: Bool, doNotDisturb: Bool) -> Bool {
        switch mode {
        case .off: false
        case .whenHidden: !petVisible && !doNotDisturb
        case .always: !doNotDisturb
        }
    }
}
