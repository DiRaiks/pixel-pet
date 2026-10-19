import Foundation
import IOKit.ps
import PetCore

/// Battery level and power source, from IOKit's power-source notifications (no polling, no permission).
@MainActor
final class PowerMonitor {
    private var source: CFRunLoopSource?
    private let onChange: (PowerReading) -> Void

    init(onChange: @escaping (PowerReading) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard source == nil, let loop = IOPSNotificationCreateRunLoopSource({ info in
            guard let info else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.report() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        source = loop
        report()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func report() {
        onChange(Self.read())
    }

    static func read() -> PowerReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerReading(percent: nil, onAC: true)
        }
        let onAC = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSACPowerValue
        for item in list {
            // A CFDictionary only bridges to a Swift dictionary through NSDictionary.
            guard let d = (IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as NSDictionary?) as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return PowerReading(percent: current * 100 / max, onAC: onAC)
        }
        return PowerReading(percent: nil, onAC: onAC)
    }
}
