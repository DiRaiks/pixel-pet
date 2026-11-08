import AppKit
import PetCore
import Sparkle

/// Updates through Sparkle, shown our way: instead of Sparkle's windows a new version arrives as a box by the
/// pet and the choices are on the update card. Only the signed release build checks: `scripts/bundle.sh`
/// writes the feed and the public key into its Info.plist, a build from source has neither and never asks.
///
/// Sparkle checks the signed feed and the download against that EdDSA key before it replaces the app.
@MainActor
final class UpdateCenter: NSObject {
    let model = UpdateModel()
    private var updater: SPUUpdater?

    /// Show the box, unpack it, or take it away (`PetController.setParcel`).
    var onParcel: ((PetController.Parcel?) -> Void)?
    /// Open (true) or close the card. However it closes (a button, a click elsewhere, Esc, another card),
    /// `cardClosed()` must follow.
    var onCard: ((Bool) -> Void)?

    /// Sparkle's open questions; each is answered exactly once, then dropped.
    private var choice: ((SPUUserUpdateChoice) -> Void)?
    private var cancel: (() -> Void)?
    private var acknowledge: (() -> Void)?
    private var expected: UInt64 = 0
    private var received: UInt64 = 0

    /// Whether this build can update at all.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["SUFeedURL"] as? String)?.isEmpty == false && (info["SUPublicEDKey"] as? String)?.isEmpty == false
    }

    var isAvailable: Bool { updater != nil }

    /// Starts Sparkle when the build is set up for it. `checks` is the "Check for updates" setting.
    func start(checks: Bool) {
        guard Self.isConfigured, updater == nil else { return }
        model.current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        // Set before starting, so with checks off Sparkle never schedules one.
        updater.automaticallyChecksForUpdates = checks
        do {
            try updater.start()
        } catch {
            NSLog("PixelPet: updater didn't start: \(error.localizedDescription)")
            return
        }
        self.updater = updater
        model.installsAutomatically = updater.automaticallyDownloadsUpdates
        model.onInstallAutomatically = { [weak self] in self?.installsAutomatically = $0 }
        model.onUpdate = { [weak self] in self?.install() }
        model.onLater = { [weak self] in self?.later() }
        model.onSkip = { [weak self] in self?.skip() }
        model.onRestart = { [weak self] in self?.restart() }
        model.onCancel = { [weak self] in self?.cancelNow() }
        model.onClose = { [weak self] in self?.onCard?(false) }
    }

    /// The "Check for updates" setting: off means no requests unless asked from the menu.
    var checksAutomatically: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    /// Sparkle's own "download and install automatically" (kept in its defaults, not in the config).
    var installsAutomatically: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            updater?.automaticallyDownloadsUpdates = newValue
            model.installsAutomatically = newValue
        }
    }

    /// An offer or an install in progress that the card can show.
    private var hasLiveOffer: Bool {
        switch model.phase {
        case .available, .ready: choice != nil
        case .downloading, .preparing: true
        default: false
        }
    }

    /// The menu's "Check for Updates…". With a check already running in the background there's nothing to
    /// show yet, unless it already found something.
    func checkNow() {
        guard let updater else { return }
        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        } else if hasLiveOffer {
            onCard?(true)
        }
    }

    /// A check as the daily one does it, in the background (`--update-check-now`, for trying updates out).
    /// Like the daily one, not with checks turned off.
    func checkInBackground() {
        guard checksAutomatically else { return }
        updater?.checkForUpdatesInBackground()
    }

    /// The app started: if it's newer than the version that ran last, however it was installed, the card
    /// says so. False for the first run and for the same or an older version.
    func welcome(after lastVersion: String?) -> Bool {
        guard let lastVersion, AppVersion.isNewer(model.current, than: lastVersion) else { return false }
        model.version = model.current
        model.phase = .updated
        return true
    }

    // MARK: Buttons

    /// Answers Sparkle's open question, once.
    private func answer(_ choice: SPUUserUpdateChoice) {
        let reply = self.choice
        self.choice = nil
        reply?(choice)
    }

    private func install() {
        guard choice != nil else { return }
        // The buttons go at once: a second click mustn't dismiss what's starting.
        model.phase = .downloading(received: 0, expected: model.size)
        onParcel?(.unpacking)
        answer(.install)
    }

    /// "Later" on the offer: the box goes, Sparkle asks again at its next check. "On quit" when it's ready:
    /// Sparkle installs it as the app quits.
    private func later() {
        guard choice != nil else { return }
        onParcel?(nil)
        onCard?(false)
        answer(.dismiss)
    }

    private func skip() {
        guard choice != nil else { return }
        onParcel?(nil)
        onCard?(false)
        answer(.skip)
    }

    private func restart() {
        guard choice != nil else { return }
        model.phase = .preparing(nil)
        answer(.install)
    }

    private func cancelNow() {
        let cancel = self.cancel
        self.cancel = nil
        onParcel?(nil)
        onCard?(false)
        cancel?()
    }

    /// The card closed, however. A check in progress is called off; a result is acknowledged; an offer keeps
    /// waiting as the box, and a download goes on.
    func cardClosed() {
        switch model.phase {
        case .checking:
            let cancel = self.cancel
            self.cancel = nil
            cancel?()
        case .upToDate, .failed, .updated:
            let ack = acknowledge
            acknowledge = nil
            ack?()
        case .available, .downloading, .preparing, .ready:
            break
        }
    }
}

extension UpdateCenter: @MainActor SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns automatic checks on (SUEnableAutomaticChecks), so Sparkle shouldn't ask; if it
        // does, the setting answers.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: checksAutomatically, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        cancel = cancellation
        model.phase = .checking
        onCard?(true)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // The feed is signed, but a version that isn't one would still end up in links and the config.
        guard AppVersion.isValid(appcastItem.displayVersionString) else {
            reply(.dismiss)
            return
        }
        choice = reply
        cancel = nil
        model.version = appcastItem.displayVersionString
        model.size = appcastItem.contentLength
        switch state.stage {
        case .downloaded:
            model.phase = .ready
            onParcel?(.waiting)
        case .installing:
            model.phase = .preparing(nil)
            onParcel?(.unpacking)
        default:
            model.phase = .available
            onParcel?(.waiting)
        }
        // A check from the menu opens the card at once; a scheduled one leaves the box to be clicked.
        if state.userInitiated { onCard?(true) }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledge = acknowledgement
        cancel = nil
        model.phase = .upToDate
        onCard?(true)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledge = acknowledgement
        cancel = nil
        choice = nil
        model.phase = .failed(error.localizedDescription)
        onParcel?(nil)
        onCard?(true)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancel = cancellation
        expected = 0
        received = 0
        model.phase = .downloading(received: 0, expected: 0)
        onParcel?(.unpacking)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expected = expectedContentLength
        model.phase = .downloading(received: received, expected: expected)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        model.phase = .downloading(received: received, expected: expected)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancel = nil
        model.phase = .preparing(nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.phase = .preparing(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        choice = reply
        model.phase = .ready
        onParcel?(.waiting)
        onCard?(true)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        model.phase = .preparing(nil)
        onParcel?(.unpacking)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    /// Sparkle ended the session: nothing is waiting on an answer any more. A result on screen stays until
    /// it's closed; anything else goes.
    func dismissUpdateInstallation() {
        choice = nil
        cancel = nil
        acknowledge = nil
        switch model.phase {
        case .upToDate, .failed, .updated:
            break
        default:
            onParcel?(nil)
            onCard?(false)
        }
    }

    func showUpdateInFocus() {
        onCard?(true)
    }
}
