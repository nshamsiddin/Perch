import AppKit
import SwiftUI
import Combine

/// Owns the notch window, hosts the SwiftUI island, resolves geometry, and drives the
/// hover-to-expand / collapse behavior. Re-resolves geometry on screen reconfiguration.
final class NotchWindowController {
    let state: IslandState
    private let services: AppServices
    private var window: NotchWindow!
    private var container: IslandContainerView!
    private var hostingView: IslandHostingView<IslandRootView>!

    private var layout: IslandLayout
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var mouseSyncTimer: Timer?
    private var lastMouseClaimed = false

    private let collapseDelay: TimeInterval = 0.35

    init(state: IslandState, services: AppServices) {
        self.state = state
        self.services = services
        self.layout = IslandLayout(geometry: state.geometry)
        buildWindow()
        observeScreenChanges()
        observeFeatureToggles()
        resolveGeometry()
        startMouseSyncTimer()
    }

    /// Builds the layout from the current geometry and the live feature toggles, which decide
    /// whether the expanded panel reserves its top content row.
    private func makeLayout() -> IslandLayout {
        IslandLayout(geometry: state.geometry,
                     mediaEnabled: state.mediaEnabled,
                     batteryEnabled: state.batteryEnabled)
    }

    // MARK: - Setup

    private func buildWindow() {
        layout = makeLayout()
        window = NotchWindow(contentRect: layout.windowFrame)

        container = IslandContainerView(frame: CGRect(origin: .zero, size: layout.windowSize))
        container.controller = self
        container.autoresizingMask = [.width, .height]

        hostingView = IslandHostingView(rootView: IslandRootView(state: state, services: services))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        // Let the AppKit container own hit-testing/click-through.
        hostingView.translatesAutoresizingMaskIntoConstraints = true

        container.addSubview(hostingView)
        window.contentView = container
        window.orderFrontRegardless()
    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.resolveGeometry() }
            .store(in: &cancellables)
    }

    /// Toggling media/battery can collapse or restore the panel's content row, which changes the
    /// reserved window height — so re-apply the layout (and window frame) when those flags change.
    private func observeFeatureToggles() {
        state.$mediaEnabled.combineLatest(state.$batteryEnabled)
            .map { [$0, $1] }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLayout() }
            .store(in: &cancellables)
    }

    // MARK: - Geometry

    func resolveGeometry() {
        state.geometry = NotchGeometry.resolve()
        applyLayout()
    }

    /// Rebuilds the layout from current geometry + toggles and resizes the window/container to match.
    private func applyLayout() {
        layout = makeLayout()
        window.setFrame(layout.windowFrame, display: true)
        container.frame = CGRect(origin: .zero, size: layout.windowSize)
        container.updateTrackingAreas()
    }

    // MARK: - Hover rects (queried by the container)

    /// Region that should claim clicks (everything else passes through).
    func currentInteractiveRect() -> CGRect {
        switch state.mode {
        case .collapsed: return layout.collapsedRect(width: currentCollapsedWidth())
        case .expanded:  return layout.expandedInteractiveRect(sessionCount: state.visibleAgentSessions.count,
                                                             approvalCount: state.agentApprovalCount)
        }
    }

    /// Region where the overlay participates in mouse routing (clicks + hover). Wider than
    /// `currentInteractiveRect` while collapsed so hover-to-expand still works.
    func shouldClaimMouseEvents(at point: CGPoint) -> Bool {
        if currentInteractiveRect().contains(point) { return true }
        switch state.mode {
        case .collapsed:
            return layout.hoverHotZone(width: currentCollapsedWidth()).contains(point)
        case .expanded:
            return layout.expandedVisibleRect(sessionCount: state.visibleAgentSessions.count,
                                              approvalCount: state.agentApprovalCount).contains(point)
        }
    }

    /// Visual width of the collapsed island, mirroring `IslandRootView`'s presentation precedence
    /// (volume HUD > peek > agent live > now-playing compact > bare pill) so hit/hover rects match
    /// the pixels.
    private func currentCollapsedWidth() -> CGFloat {
        let notchWidth = state.geometry.notchWidth
        if state.volumeHUD != nil { return notchWidth + 200 }             // volume HUD
        if state.currentActivity != nil { return notchWidth + 220 }       // peek
        if state.hasActiveAgents { return layout.compactWidth }           // agent ears
        if state.nowPlayingActive { return layout.compactWidth }          // now-playing ears
        return notchWidth                                                  // bare pill
    }

    /// Stable tracking region covering the whole top area.
    func currentHoverRect() -> CGRect {
        layout.expandedRect
    }

    // MARK: - Hover behavior

    func handleMouseMoved(at point: CGPoint) {
        if state.mode == .collapsed {
            if layout.hoverHotZone(width: currentCollapsedWidth()).contains(point) {
                expand()
            }
        } else {
            // Staying anywhere within the panel keeps it open.
            if layout.expandedRect.contains(point) {
                cancelScheduledCollapse()
            }
        }
    }

    func handleHoverExit() {
        if state.mode == .expanded {
            scheduleCollapse()
        }
    }

    // MARK: - Mouse pass-through

    /// Polls the global cursor and toggles `ignoresMouseEvents` so transparent dead zones around
    /// the notch pass clicks/hover to apps below. Hit-testing alone is unreliable at
    /// `CGShieldingWindowLevel` when the window frame is much larger than the visible island.
    private func startMouseSyncTimer() {
        mouseSyncTimer?.invalidate()
        mouseSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.syncMouseEventHandling()
        }
        if let mouseSyncTimer {
            RunLoop.main.add(mouseSyncTimer, forMode: .common)
        }
    }

    private func syncMouseEventHandling() {
        guard let window, let contentView = window.contentView else { return }

        if state.isHiddenForFullScreen {
            if !window.ignoresMouseEvents { window.ignoresMouseEvents = true }
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = contentView.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let claim = shouldClaimMouseEvents(at: windowPoint)
        let ignore = !claim
        if window.ignoresMouseEvents != ignore {
            window.ignoresMouseEvents = ignore
        }

        if claim {
            handleMouseMoved(at: windowPoint)
        } else if state.mode == .expanded, lastMouseClaimed {
            handleHoverExit()
        }
        lastMouseClaimed = claim
    }

    private func expand() {
        cancelScheduledCollapse()
        guard state.mode != .expanded else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            state.setMode(.expanded)
        }
    }

    private func scheduleCollapse() {
        cancelScheduledCollapse()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                self.state.setMode(.collapsed)
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    // MARK: - Full-screen visibility

    func setHiddenForFullScreen(_ hidden: Bool) {
        state.isHiddenForFullScreen = hidden
        window.animator().alphaValue = hidden ? 0 : 1
        window.ignoresMouseEvents = hidden
    }
}
