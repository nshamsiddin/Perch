import AppKit
import Combine
import SwiftUI

/// Central hub wiring the shared state to the feature services and exposing the user-facing
/// actions the SwiftUI island invokes. Injected into the view tree as an `EnvironmentObject`.
final class AppServices: ObservableObject {
    let state: IslandState
    let media: MediaService
    let battery: BatteryService
    let volume: VolumeService
    let activity: ActivityCenter
    let powerMode: PowerModeService
    let agents: AgentStatusService
    let agentFocus: AgentFocusService
    let agentNotifications: AgentNotificationService
    let agentCommands: AgentCommandService
    let agentAudit: AgentAuditService

    private var cancellables = Set<AnyCancellable>()

    init(state: IslandState) {
        self.state = state
        self.activity = ActivityCenter(state: state)
        self.media = MediaService(state: state, activity: activity)
        self.battery = BatteryService(state: state, activity: activity)
        self.volume = VolumeService(state: state)
        self.powerMode = PowerModeService()
        self.agentFocus = AgentFocusService()
        self.agentNotifications = AgentNotificationService()
        self.agentCommands = AgentCommandService()
        self.agentAudit = AgentAuditService()
        self.agents = AgentStatusService(state: state, activity: activity)

        // Tapping a "waiting" notification refocuses that agent (if it's still active).
        agentNotifications.onActivate = { [weak self] sessionID in
            guard let self,
                  let session = self.state.agentSessions.first(where: { $0.id == sessionID })
            else { return }
            self.focusAgent(session)
        }
        // When a session newly starts waiting, alert (if enabled). The amber flash is driven by
        // `state.agentAttention`, set inside the status service itself.
        agents.onNewWaiting = { [weak self] session in
            guard let self, self.state.notifyOnWaiting else { return }
            self.agentNotifications.notifyWaiting(session)
        }
    }

    /// Refocuses the terminal tab / editor window the given agent session is running in.
    func focusAgent(_ session: AgentSession) {
        agentFocus.focus(session)
    }

    // MARK: - Agent control actions

    /// Approves the session's pending tool call, optionally with a short steering note.
    func approveAgent(_ session: AgentSession, note: String? = nil) {
        agentCommands.approve(session, note: note)
        agentAudit.record(.allow, session: session, note: note)
    }

    /// Denies the session's pending tool call.
    func denyAgent(_ session: AgentSession, reason: String? = nil) {
        agentCommands.deny(session, reason: reason)
        agentAudit.record(.deny, session: session, note: reason)
    }

    /// Best-effort stop of a running agent (SIGINT + deny-next).
    func stopAgent(_ session: AgentSession) {
        agentCommands.stop(session)
        agentAudit.record(.stop, session: session)
    }

    // MARK: - Gating snooze

    /// Pauses gate blocking until `until`. Pass `AgentCommandService.gatingPausedIndefinite` for
    /// "until restart".
    func pauseGating(until: Date) {
        state.gatingPausedUntil = until
        syncGatingConfig()
    }

    /// Clears any active gating snooze and resumes normal blocking behavior.
    func resumeGating() {
        state.gatingPausedUntil = nil
        syncGatingConfig()
    }

    func start() {
        // Volume is always on (it only reacts to system volume changes, no toggle exposed).
        volume.start()
        // Feature services start only when their toggle is on; the observers below keep them in
        // sync with later changes so disabling a feature stops its background work entirely.
        if state.batteryEnabled { battery.start() }
        if state.mediaEnabled { media.start() }
        agentNotifications.start()
        if state.agentsEnabled { agents.start() }
        // Publish the initial gating config so the gate hooks know whether to block on the island.
        syncGatingConfig()
        observeFeatureToggles()
    }

    /// Tells the gate hooks whether to route tool calls through the island. Gating is on only when
    /// both the AI feature and Control are enabled, so turning either off restores normal behavior.
    private func syncGatingConfig() {
        let pausedUntil = state.isGatingPaused ? state.gatingPausedUntil : nil
        agentCommands.setGating(enabled: state.agentsControlActive, pausedUntil: pausedUntil)
    }

    func stop() {
        cancellables.removeAll()
        battery.stop()
        media.stop()
        volume.stop()
        agents.stop()
    }

    /// Starts/stops each feature service as its toggle flips, and clears the now-stale state so the
    /// island collapses immediately when a feature is turned off. `dropFirst` skips the initial
    /// value (already handled by `start()`); `removeDuplicates` guards against redundant restarts.
    private func observeFeatureToggles() {
        state.$mediaEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.media.start()
                } else {
                    self.media.stop()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.state.nowPlaying = .empty
                        self.state.artwork = nil
                    }
                }
            }
            .store(in: &cancellables)

        state.$batteryEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.battery.start()
                } else {
                    self.battery.stop()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.state.battery = .unknown
                    }
                }
            }
            .store(in: &cancellables)

        state.$agentsEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.agents.start()
                } else {
                    self.agents.stop()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.state.agentSessions = []
                    }
                }
                // Disabling AI Agents also disables gating (control depends on monitoring).
                self.syncGatingConfig()
            }
            .store(in: &cancellables)

        // Toggling Control just republishes the gating config; the gate hooks pick it up on their
        // next event. No service to start/stop — the back-channel files are always available.
        state.$agentsControlEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.syncGatingConfig() }
            .store(in: &cancellables)

        state.$gatingPausedUntil
            .sink { [weak self] until in
                guard let self else { return }
                if let until, until <= Date() {
                    self.state.gatingPausedUntil = nil
                }
                self.syncGatingConfig()
            }
            .store(in: &cancellables)
    }
}
