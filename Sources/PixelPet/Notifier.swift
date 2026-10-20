import AppKit
import PetCore
import UserNotifications

/// Silent system notifications: banners only, no sound or badge, one per key (a session, or the key touch),
/// replaced in place and removed once they're over. Asks for permission the first time one is posted.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// nil when not running from an app bundle (`swift run`): the notification center needs one.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()
    /// Bumped on every post or clear of a key, so a post still waiting for permission can't land after a clear.
    private var generation: [String: Int] = [:]
    /// Whether macOS lets the app post, for the hint in Settings; nil until known.
    private(set) var allowed: Bool?
    var onAllowedChange: ((Bool?) -> Void)?

    override init() {
        super.init()
        center?.delegate = self
        Task { await refreshAllowed() }
    }

    nonisolated static let hostKey = "host"

    func post(_ key: String, title: String, body: String, host: String?) {
        let token = bump(key)
        Task {
            guard await authorize(), generation[key] == token else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil
            content.threadIdentifier = key
            if let host { content.userInfo = [Self.hostKey: host] }
            try? await center?.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }

    func clear(_ key: String) {
        bump(key)
        center?.removeDeliveredNotifications(withIdentifiers: [key])
        center?.removePendingNotificationRequests(withIdentifiers: [key])
    }

    func clearAll() {
        generation.keys.forEach { bump($0) }
        center?.removeAllDeliveredNotifications()
        center?.removeAllPendingNotificationRequests()
    }

    /// Settings → Notifications → Pixel Pet.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "dev.pixelpet.PixelPet"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshAllowed() async {
        guard let center else { return }
        allowed = switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        case .denied: false
        default: nil
        }
        onAllowedChange?(allowed)
    }

    @discardableResult
    private func bump(_ key: String) -> Int {
        let next = (generation[key] ?? 0) + 1
        generation[key] = next
        return next
    }

    /// Banners only: no sound, no badge.
    private func authorize() async -> Bool {
        guard let center else { return false }
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        await refreshAllowed()
        return allowed == true
    }

    // The app is always "in front" as far as macOS knows (a menu-bar app): show the banner anyway.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// A click brings the app the session runs in to the front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let bundle = response.notification.request.content.userInfo[Self.hostKey] as? String else { return }
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
        }
    }
}

/// The words in a notification: the project and what happened, nothing from the session itself.
@MainActor
enum NoticeText {
    static func title(_ notice: AgentNotice, project: String) -> String {
        switch notice {
        case .permission: L("\(project) needs permission", "\(project) ждёт разрешения")
        case .question: L("\(project) asks a question", "\(project) задал вопрос")
        case .finished: L("\(project) is done", "\(project) готово")
        case .failed: L("\(project) stopped with an error", "\(project) остановился с ошибкой")
        }
    }

    static func body(_ notice: AgentNotice, session: AgentSession, codex: Bool) -> String {
        let what: String? = switch notice {
        case .permission: permission(session.step?.action)
        case .question: L("Waiting for an answer", "Ждёт ответа")
        case .finished(let took, let steps):
            [took.map { L("Worked \(Format.duration($0))", "Работал \(Format.duration($0))") },
             steps > 0 ? Format.steps(steps) : nil].compactMap { $0 }.joined(separator: " · ")
        case .failed: nil
        }
        let place = codex ? "Codex" : session.host?.names?.en
        return [what.flatMap { $0.isEmpty ? nil : $0 }, place].compactMap { $0 }.joined(separator: " · ")
    }

    /// Which kind of thing, never the command or the file.
    private static func permission(_ action: AgentStep.Action?) -> String {
        switch action {
        case .run: L("Wants to run a command", "Хочет выполнить команду")
        case .edit, .write: L("Wants to change a file", "Хочет изменить файл")
        case .fetch, .webSearch: L("Wants to go online", "Хочет в интернет")
        default: L("Wants to use a tool", "Хочет использовать инструмент")
        }
    }

    static let touchTitle = { L("Touch your YubiKey", "Коснитесь YubiKey") }
    static let touchBody = { L("A GPG signature waits for the key", "Подпись GPG ждёт касания ключа") }
}
