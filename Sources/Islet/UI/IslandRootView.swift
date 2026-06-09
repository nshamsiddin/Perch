import SwiftUI

/// Root SwiftUI view hosted inside the notch window. Anchors a black "island" to the top
/// center and morphs its size/shape between collapsed, activity-peek, and expanded states.
struct IslandRootView: View {
    @ObservedObject var state: IslandState
    let services: AppServices
    @Environment(\.colorScheme) private var colorScheme

    /// Opacity of the transient amber attention border, pulsed when an agent starts waiting.
    @State private var flashOpacity: Double = 0

    private var layout: IslandLayout {
        IslandLayout(geometry: state.geometry,
                     mediaEnabled: state.mediaEnabled,
                     batteryEnabled: state.batteryEnabled)
    }
    private var theme: IslandTheme { IslandTheme(scheme: colorScheme) }

    /// Island fill: collapsed/peek stay dark to blend with the physical notch; only the
    /// expanded panel follows the system Light/Dark appearance.
    private var islandFill: Color {
        presentation == .expanded ? theme.panelBackground : .black
    }

    private var islandStroke: Color {
        presentation == .expanded ? theme.panelStroke : Color.white.opacity(0.06)
    }

    /// Effective visual presentation derived from mode + transient activity + agents + now-playing.
    /// Precedence while collapsed: volume HUD > activity peek > agent live > now-playing compact > bare pill.
    private enum Presentation { case collapsed, nowPlayingCompact, agentLive, peek, volumeHUD, expanded }

    private var presentation: Presentation {
        // Hover-expanded panel wins; the volume HUD only applies to the collapsed/peek family.
        if state.mode == .expanded { return .expanded }
        if state.volumeHUD != nil { return .volumeHUD }
        if state.currentActivity != nil { return .peek }
        // A live agent indicator headlines the collapsed island over now-playing; both still
        // appear together in the expanded panel.
        if state.hasActiveAgents { return .agentLive }
        if state.nowPlayingActive { return .nowPlayingCompact }
        return .collapsed
    }

    private var islandSize: CGSize {
        switch presentation {
        case .collapsed:
            return CGSize(width: state.geometry.notchWidth, height: state.geometry.notchHeight)
        case .nowPlayingCompact, .agentLive:
            // Must match controller's compact hit/hover width (notchWidth + 2*earWidth).
            return CGSize(width: layout.compactWidth, height: state.geometry.notchHeight)
        case .peek:
            return CGSize(width: state.geometry.notchWidth + 220, height: state.geometry.notchHeight + 6)
        case .volumeHUD:
            // Must match controller's volume-HUD hit/hover width (notchWidth + 200).
            return CGSize(width: state.geometry.notchWidth + 200, height: state.geometry.notchHeight + 6)
        case .expanded:
            let visibleHeight = layout.expandedVisibleHeight(sessionCount: state.visibleAgentSessions.count)
            // Inset the panel from the window edges, leaving room for the shadow. The panel keeps
            // its own internal bottom padding (layout.panelBottomPadding) for content breathing room.
            return CGSize(
                width: layout.expandedWidth - 2 * layout.windowMarginX,
                height: visibleHeight - layout.windowMarginBottom
            )
        }
    }

    private var cornerRadii: RectangleCornerRadii {
        switch presentation {
        case .collapsed, .nowPlayingCompact, .agentLive:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 12, bottomTrailing: 12, topTrailing: 0)
        case .peek, .volumeHUD:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0)
        case .expanded:
            return RectangleCornerRadii(topLeading: 10, bottomLeading: 26, bottomTrailing: 26, topTrailing: 10)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(state.isHiddenForFullScreen ? 0 : 1)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .fill(islandFill)
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .strokeBorder(islandStroke, lineWidth: 0.5)
                )

            content
                .padding(.horizontal, presentation == .expanded ? 16 : 0)
        }
        .frame(width: islandSize.width, height: islandSize.height)
        // Amber attention border, faded out after each "agent now waiting" event.
        .overlay(
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .strokeBorder(Color.orange, lineWidth: 2)
                .opacity(flashOpacity)
        )
        .shadow(color: .orange.opacity(flashOpacity * 0.6), radius: 10)
        // Layered, downward-biased drop shadow: a tight contact shadow plus a soft ambient
        // lift. Both are offset down (positive y) so the panel hangs cleanly from the notch
        // instead of radiating an even halo around its top edge.
        .shadow(color: .black.opacity(presentation == .expanded ? theme.shadowOpacity : 0),
                radius: 4, y: 2)
        .shadow(color: .black.opacity(presentation == .expanded ? theme.shadowOpacity * 0.7 : 0),
                radius: 16, y: 11)
        .onChange(of: state.agentAttention) { newValue in
            guard newValue != nil else { return }
            flashOpacity = 0.9
            withAnimation(.easeOut(duration: 1.1)) { flashOpacity = 0 }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .collapsed:
            Color.clear
        case .nowPlayingCompact:
            NowPlayingCompactView(
                nowPlaying: state.nowPlaying,
                artwork: state.artwork,
                notchWidth: state.geometry.notchWidth,
                earWidth: layout.earWidth
            )
            .transition(.opacity)
        case .agentLive:
            AgentLiveView(
                sessions: state.visibleAgentSessions,
                notchWidth: state.geometry.notchWidth,
                earWidth: layout.earWidth
            )
            .transition(.opacity)
        case .peek:
            if let activity = state.currentActivity {
                ActivityPeekView(activity: activity, notchWidth: state.geometry.notchWidth)
                    .transition(.opacity)
            }
        case .volumeHUD:
            if let hud = state.volumeHUD {
                VolumeHUDView(hud: hud, notchWidth: state.geometry.notchWidth)
                    .transition(.opacity)
            }
        case .expanded:
            ExpandedView(state: state, services: services)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }
}
