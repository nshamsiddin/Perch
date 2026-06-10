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
    let calendar: CalendarService
    let privacy: PrivacyIndicatorService
    let menuBarReveal: MenuBarRevealService

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
        self.calendar = CalendarService(state: state, activity: activity)
        self.privacy = PrivacyIndicatorService(state: state)
        self.menuBarReveal = MenuBarRevealService(state: state)

        agentNotifications.onActivate = { [weak self] sessionID in
            guard let self,
                  let session = self.state.agentSessions.first(where: { $0.id == sessionID })
            else { return }
            self.focusAgent(session)
        }
        agents.onNewWaiting = { [weak self] session in
            guard let self, self.state.notifyOnWaiting else { return }
            self.agentNotifications.notifyWaiting(session)
        }
    }

    func focusAgent(_ session: AgentSession) {
        agentFocus.focus(session)
    }

    func approveAgent(_ session: AgentSession, note: String? = nil) {
        agentCommands.approve(session, note: note)
        agentAudit.record(.allow, session: session, note: note)
    }

    func denyAgent(_ session: AgentSession, reason: String? = nil) {
        agentCommands.deny(session, reason: reason)
        agentAudit.record(.deny, session: session, note: reason)
    }

    func stopAgent(_ session: AgentSession) {
        agentCommands.stop(session)
        agentAudit.record(.stop, session: session)
    }

    func pauseGating(until: Date) {
        state.gatingPausedUntil = until
        syncGatingConfig()
    }

    func resumeGating() {
        state.gatingPausedUntil = nil
        syncGatingConfig()
    }

    func start() {
        volume.start()
        state.mediaRemoteAvailable = MediaRemoteAdapterClient().probe()
        if state.batteryEnabled { battery.start() }
        if state.mediaEnabled && state.mediaSourceMode != .off { media.start() }
        if state.calendarEnabled { calendar.start() }
        if state.privacyEnabled { privacy.start() }
        if state.menuBarRevealEnabled { menuBarReveal.start() }
        agentNotifications.start()
        if state.agentsEnabled { agents.start() }
        syncGatingConfig()
        observeFeatureToggles()
        if state.launchAtLogin != LaunchAtLoginHelper.isEnabled() {
            state.launchAtLogin = LaunchAtLoginHelper.isEnabled()
        }
    }

    private func syncGatingConfig() {
        let pausedUntil = state.isGatingPaused ? state.gatingPausedUntil : nil
        agentCommands.setGating(enabled: state.agentsControlActive, pausedUntil: pausedUntil)
    }

    private func syncMediaService() {
        if state.mediaEnabled && state.mediaSourceMode != .off {
            media.start()
        } else {
            media.stop()
            state.nowPlaying = .empty
            state.artwork = nil
        }
    }

    func stop() {
        cancellables.removeAll()
        battery.stop()
        media.stop()
        volume.stop()
        calendar.stop()
        privacy.stop()
        menuBarReveal.stop()
        agents.stop()
    }

    private func observeFeatureToggles() {
        state.$mediaEnabled
            .removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.syncMediaService() }
            .store(in: &cancellables)

        state.$mediaSourceMode
            .removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.syncMediaService() }
            .store(in: &cancellables)

        state.$batteryEnabled
            .removeDuplicates().dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.battery.start() }
                else {
                    self.battery.stop()
                    withAnimation(.easeInOut(duration: 0.2)) { self.state.battery = .unknown }
                }
            }
            .store(in: &cancellables)

        state.$agentsEnabled
            .removeDuplicates().dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.agents.start() }
                else {
                    self.agents.stop()
                    withAnimation(.easeInOut(duration: 0.2)) { self.state.agentSessions = [] }
                }
                self.syncGatingConfig()
            }
            .store(in: &cancellables)

        state.$calendarEnabled
            .removeDuplicates().dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.calendar.start() }
                else {
                    self.calendar.stop()
                    self.state.nextCalendarEvent = nil
                }
            }
            .store(in: &cancellables)

        state.$privacyEnabled
            .removeDuplicates().dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.privacy.start() }
                else { self.privacy.stop() }
            }
            .store(in: &cancellables)

        state.$menuBarRevealEnabled
            .removeDuplicates().dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.menuBarReveal.start() }
                else { self.menuBarReveal.stop() }
            }
            .store(in: &cancellables)

        state.$agentsControlEnabled
            .removeDuplicates().dropFirst()
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
