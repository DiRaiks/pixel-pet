import AppKit
import CoreAudio
import CoreMediaIO
import Network
import PetCore

/// Watches the Mac for the things the pet reacts to: where sound goes and whether it plays, the mic and
/// camera, heat, low power, the network, new screenshots and the system theme. Everything is event-driven
/// (property listeners and notifications), needs no permission, and reads no content: only on/off flags.
@MainActor
final class MacMonitor {
    /// The debounced state changed. `animate` is false for the first reading after starting and for the reset
    /// when stopping: headphones already on at launch aren't put on again.
    var onChange: ((MacState, _ animate: Bool) -> Void)?
    var onScreenshot: (() -> Void)?
    /// The appearance switched: true for dark.
    var onTheme: ((Bool) -> Void)?

    private(set) var state = MacState()
    private var running = false
    /// While starting, the listeners each refresh; publish once at the end.
    private var starting = false
    private var published = false
    private var sound = SoundDebounce()
    private var network = OfflineDebounce()
    private var online = true
    private var recheck: DispatchWorkItem?

    private struct AudioListener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private struct CameraListener {
        let object: CMIOObjectID
        var address: CMIOObjectPropertyAddress
        let block: CMIOObjectPropertyListenerBlock
    }
    private var systemAudio: [AudioListener] = []
    private var deviceAudio: [AudioListener] = []
    private var cameraListeners: [CameraListener] = []
    private var cameraListListener: CameraListener?
    private var pathMonitor: NWPathMonitor?
    private var screenshots: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var theme: ThemeObserver?
    private var dark: Bool?

    func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        on ? start() : stop()
    }

    private func start() {
        starting = true
        published = false
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            if let l = listen(AudioObjectID(kAudioObjectSystemObject), selector, { [weak self] in self?.devicesChanged() }) {
                systemAudio.append(l)
            }
        }
        devicesChanged()
        watchCameras()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.online = ok; self?.refresh() } }
        }
        monitor.start(queue: DispatchQueue(label: "dev.pixelpet.network"))
        pathMonitor = monitor

        // New screenshots, as Spotlight indexes them; what's already there doesn't count.
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@", Date() as NSDate)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let added = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [Any])?.isEmpty == false
            MainActor.assumeIsolated { if added { self?.onScreenshot?() } }
        })
        query.start()
        screenshots = query

        dark = Self.isDark
        theme = ThemeObserver { [weak self] in self?.themeChanged() }
        starting = false
        refresh()
    }

    private func stop() {
        for l in systemAudio + deviceAudio { remove(l) }
        systemAudio = []
        deviceAudio = []
        for l in cameraListeners { remove(l) }
        cameraListeners = []
        if let l = cameraListListener { remove(l) }
        cameraListListener = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        theme = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        screenshots?.stop()
        screenshots = nil
        recheck?.cancel()
        recheck = nil
        sound = SoundDebounce()
        network = OfflineDebounce()
        online = true
        dark = nil
        publish(MacState(), animate: false)
    }

    // MARK: State

    private func refresh() {
        guard running, !starting else { return }
        let now = Date()
        let output = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let playing = output.map { Self.isRunning($0) } ?? false
        var next = MacState()
        next.headphones = output.map(Self.isHeadphones) ?? false
        next.music = sound.update(playing: playing, at: now)
        next.onAir = (input.map { Self.isRunning($0) } ?? false) || camerasInUse()
        next.hot = [.serious, .critical].contains(ProcessInfo.processInfo.thermalState)
        next.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        next.offline = network.update(online: online, at: now)
        publish(next, animate: published)
        published = true
        scheduleRecheck(now)
    }

    private func publish(_ next: MacState, animate: Bool) {
        guard next != state else { return }
        state = next
        onChange?(next, animate)
    }

    /// The debounces flip without a new event: look again when one is due.
    private func scheduleRecheck(_ now: Date) {
        recheck?.cancel()
        recheck = nil
        guard let due = [sound.nextCheck(after: now), network.nextCheck()].compactMap({ $0 }).min() else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        recheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, due.timeIntervalSince(now) + 0.1), execute: work)
    }

    private func themeChanged() {
        let now = Self.isDark
        if ThemeChange.moment(from: dark, toDark: now) != nil { onTheme?(now) }
        dark = now
    }

    /// Read from the global preferences rather than the app's appearance, which may not have caught up yet
    /// when the notification arrives.
    private static var isDark: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return style == "Dark"
    }

    // MARK: Audio devices

    /// The default devices changed: follow the new ones (whether they run, and the built-in jack).
    private func devicesChanged() {
        for l in deviceAudio { remove(l) }
        deviceAudio = []
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            guard let device = Self.defaultDevice(selector) else { continue }
            if let l = listen(device, kAudioDevicePropertyDeviceIsRunningSomewhere, { [weak self] in self?.refresh() }) {
                deviceAudio.append(l)
            }
            if selector == kAudioHardwarePropertyDefaultOutputDevice,
               let l = listen(device, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput,
                              { [weak self] in self?.refresh() }) {
                deviceAudio.append(l)
            }
        }
        refresh()
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        guard let id = uint32(AudioObjectID(kAudioObjectSystemObject), selector), id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// Some client has IO open on a real device. Virtual and aggregate devices (loopback drivers, call apps'
    /// own devices) are always open somewhere, so they don't count.
    private static func isRunning(_ device: AudioObjectID) -> Bool {
        let transport = uint32(device, kAudioDevicePropertyTransportType)
        guard ![kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                kAudioDeviceTransportTypeAutoAggregate].contains(transport) else { return false }
        return (uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }

    /// Bluetooth audio, or the built-in output switched to its headphone jack.
    private static func isHeadphones(_ device: AudioObjectID) -> Bool {
        let transport = uint32(device, kAudioDevicePropertyTransportType)
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return true }
        let headphoneJack: UInt32 = 0x6864_706E // 'hdpn'
        return transport == kAudioDeviceTransportTypeBuiltIn
            && uint32(device, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput) == headphoneJack
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ action: @escaping @MainActor () -> Void) -> AudioListener? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { action() } }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        return AudioListener(object: object, address: address, block: block)
    }

    private func remove(_ l: AudioListener) {
        var address = l.address
        AudioObjectRemovePropertyListenerBlock(l.object, &address, .main, l.block)
    }

    // MARK: Cameras

    private func watchCameras() {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.followCameras() }
        }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block) == noErr {
            cameraListListener = CameraListener(object: CMIOObjectID(kCMIOObjectSystemObject), address: address, block: block)
        }
        followCameras()
    }

    private func followCameras() {
        for l in cameraListeners { remove(l) }
        cameraListeners = []
        for camera in Self.cameras() {
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.refresh() } }
            if CMIOObjectAddPropertyListenerBlock(camera, &address, .main, block) == noErr {
                cameraListeners.append(CameraListener(object: camera, address: address, block: block))
            }
        }
        refresh()
    }

    private func camerasInUse() -> Bool {
        Self.cameras().contains { camera in
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr
                && running != 0
        }
    }

    private static func cameras() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr
        else { return [] }
        return ids
    }

    private func remove(_ l: CameraListener) {
        var address = l.address
        CMIOObjectRemovePropertyListenerBlock(l.object, &address, .main, l.block)
    }
}

/// The theme change arrives as a distributed notification, which an inactive app only gets if it asks for
/// immediate delivery (the selector-based API is the one that takes a suspension behavior).
private final class ThemeObserver: NSObject {
    private let action: @MainActor @Sendable () -> Void

    init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(changed), name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func changed() {
        let action = self.action
        DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
    }
}
