import SwiftUI
import Combine

/// Drives the transient live-activity peek. Other services call `show(...)` to surface a
/// brief event (track change, file stashed, battery plugged, etc). Reframed from system
/// notifications, which have no public read API on modern macOS.
final class ActivityCenter: ObservableObject {
    private let state: IslandState
    private var clearWorkItem: DispatchWorkItem?
    private let visibleDuration: TimeInterval = 3.0

    init(state: IslandState) {
        self.state = state
    }

    func show(symbol: String, text: String) {
        clearWorkItem?.cancel()

        let activity = Activity(symbol: symbol, text: text)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            state.currentActivity = activity
        }

        scheduleClear(after: visibleDuration)
    }

    private func scheduleClear(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.state.mode == .expanded {
                self.scheduleClear(after: self.visibleDuration)
                return
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                self.state.currentActivity = nil
            }
        }
        clearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
