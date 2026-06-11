import Foundation
import IOKit.ps

/// Reads battery / power state via IOKit power sources and pushes updates into `IslandState`.
/// Updates are event-driven through `IOPSNotificationCreateRunLoopSource`, with no polling.
final class BatteryService {
    private let state: IslandState
    private let activity: ActivityCenter
    private var runLoopSource: CFRunLoopSource?
    private var lastPluggedIn: Bool?

    init(state: IslandState, activity: ActivityCenter) {
        self.state = state
        self.activity = activity
    }

    func start() {
        update()

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { service.update() }
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }

    private func update() {
        let status = Self.read()

        if let last = lastPluggedIn, last != status.isPluggedIn, status.hasBattery {
            let plugText: String
            if status.isPluggedIn, let watts = status.adapterWatts {
                plugText = "\(watts)W connected"
            } else if status.isPluggedIn {
                plugText = "Power connected"
            } else {
                plugText = "On battery"
            }
            activity.show(
                symbol: status.isPluggedIn ? "powerplug.fill" : "battery.75",
                text: plugText
            )
        }
        lastPluggedIn = status.hasBattery ? status.isPluggedIn : nil

        state.battery = status
    }

    static func read() -> BatteryStatus {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return .unknown
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = desc[kIOPSPowerSourceStateKey] as? String
            let pluggedIn = (powerState == kIOPSACPowerValue) || isCharging

            let percentage: Int
            if let current, let maxCap, maxCap > 0 {
                percentage = Int((Double(current) / Double(maxCap)) * 100.0)
            } else {
                percentage = current ?? -1
            }

            let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?
                .takeRetainedValue() as? [String: Any]
            let adapterWatts = pluggedIn ? Self.parseAdapterWatts(from: adapterDetails) : nil

            return BatteryStatus(
                percentage: percentage,
                isCharging: isCharging,
                isPluggedIn: pluggedIn,
                hasBattery: true,
                adapterWatts: adapterWatts
            )
        }

        return .unknown
    }

    static func parseAdapterWatts(from details: [String: Any]?) -> Int? {
        guard let watts = details?[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 else { return nil }
        return watts
    }
}
