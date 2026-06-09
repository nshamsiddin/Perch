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
    private var hostingView: NSHostingView<IslandRootView>!

    private var layout: IslandLayout
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private let collapseDelay: TimeInterval = 0.35

    init(state: IslandState, services: AppServices) {
        self.state = state
        self.services = services
        self.layout = IslandLayout(geometry: state.geometry)
        buildWindow()
        observeScreenChanges()
        resolveGeometry()
    }

    // MARK: - Setup

    private func buildWindow() {
        layout = IslandLayout(geometry: state.geometry)
        window = NotchWindow(contentRect: layout.windowFrame)

        container = IslandContainerView(frame: CGRect(origin: .zero, size: layout.windowSize))
        container.controller = self
        container.autoresizingMask = [.width, .height]

        hostingView = NSHostingView(rootView: IslandRootView(state: state, services: services))
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

    // MARK: - Geometry

    func resolveGeometry() {
        let geometry = NotchGeometry.resolve()
        state.geometry = geometry
        layout = IslandLayout(geometry: geometry)
        window.setFrame(layout.windowFrame, display: true)
        container.frame = CGRect(origin: .zero, size: layout.windowSize)
        container.updateTrackingAreas()
    }

    // MARK: - Hover rects (queried by the container)

    /// Region that should claim clicks (everything else passes through).
    func currentInteractiveRect() -> CGRect {
        switch state.mode {
        case .collapsed: return layout.collapsedRect(width: currentCollapsedWidth())
        case .expanded:  return layout.expandedRect
        }
    }

    /// Visual width of the collapsed island, mirroring `IslandRootView`'s presentation precedence
    /// (volume HUD > peek > now-playing compact > bare pill) so hit/hover rects match the pixels.
    private func currentCollapsedWidth() -> CGFloat {
        let notchWidth = state.geometry.notchWidth
        if state.volumeHUD != nil { return notchWidth + 200 }             // volume HUD
        if state.currentActivity != nil { return notchWidth + 220 }       // peek
        if state.nowPlaying.hasContent { return layout.compactWidth }     // now-playing ears
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
