import AppKit
import Combine

/// Central hub wiring the shared state to the feature services and exposing the user-facing
/// actions the SwiftUI island invokes. Injected into the view tree as an `EnvironmentObject`.
final class AppServices: ObservableObject {
    let state: IslandState
    let media: MediaService
    let battery: BatteryService
    let volume: VolumeService
    let activity: ActivityCenter
    let powerMode: PowerModeService

    init(state: IslandState) {
        self.state = state
        self.activity = ActivityCenter(state: state)
        self.media = MediaService(state: state, activity: activity)
        self.battery = BatteryService(state: state, activity: activity)
        self.volume = VolumeService(state: state)
        self.powerMode = PowerModeService()
    }

    func start() {
        battery.start()
        media.start()
        volume.start()
    }

    func stop() {
        battery.stop()
        media.stop()
        volume.stop()
    }
}
