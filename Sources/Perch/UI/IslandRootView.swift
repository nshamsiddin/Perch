import SwiftUI

/// Root SwiftUI view hosted inside the notch window. Anchors a black "island" to the top
/// center and morphs its size/shape between collapsed, activity-peek, and expanded states.
struct IslandRootView: View {
    @ObservedObject var state: IslandState
    let services: AppServices
    @Environment(\.colorScheme) private var colorScheme

    @State private var flashOpacity: Double = 0

    private var layout: IslandLayout {
        IslandLayout(geometry: state.geometry,
                     mediaEnabled: state.mediaEnabled,
                     batteryEnabled: state.batteryEnabled,
                     calendarEnabled: state.calendarEnabled,
                     menuBarRevealActive: state.menuBarRevealActive)
    }
    private var theme: IslandTheme { IslandTheme(scheme: colorScheme) }

    private var registry: PresentationRegistry {
        PresentationRegistry(state: state, layout: layout)
    }

    private var presentation: IslandCollapsedPresentation {
        registry.presentation
    }

    private var islandFill: Color {
        presentation == .expanded ? theme.panelBackground : .black
    }

    private var islandStroke: Color {
        presentation == .expanded ? theme.panelStroke : Color.white.opacity(0.06)
    }

    private var islandSize: CGSize {
        let notchWidth = state.geometry.notchWidth
        let notchHeight = state.geometry.notchHeight
        switch presentation {
        case .collapsed:
            return CGSize(width: notchWidth, height: notchHeight)
        case .clock:
            return CGSize(width: registry.collapsedWidth(notchWidth: notchWidth), height: notchHeight)
        case .nowPlayingCompact, .agentLive, .calendarCountdown, .privacyIndicator:
            return CGSize(width: layout.compactWidth, height: notchHeight)
        case .peek:
            return CGSize(width: notchWidth + 220, height: notchHeight + 6)
        case .volumeHUD:
            return CGSize(width: notchWidth + 200, height: notchHeight + 6)
        case .expanded:
            let visibleHeight = layout.expandedVisibleHeight(
                sessionCount: state.visibleAgentSessions.count,
                approvalCount: state.agentApprovalCount,
                menuBarRevealActive: state.menuBarRevealActive
            )
            return CGSize(
                width: layout.expandedWidth - 2 * layout.windowMarginX,
                height: visibleHeight - layout.windowMarginBottom
            )
        }
    }

    private var cornerRadii: RectangleCornerRadii {
        switch presentation {
        case .collapsed, .nowPlayingCompact, .agentLive, .calendarCountdown, .privacyIndicator, .clock:
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
                .allowsHitTesting(false)
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
        .overlay(
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .strokeBorder(Color.orange, lineWidth: 2)
                .opacity(flashOpacity)
        )
        .shadow(color: .orange.opacity(flashOpacity * 0.6), radius: 10)
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
        case .clock:
            ClockCompactView(notchWidth: state.geometry.notchWidth, earWidth: layout.earWidth)
        case .nowPlayingCompact:
            NowPlayingCompactView(
                nowPlaying: state.nowPlaying,
                artwork: state.artwork,
                notchWidth: state.geometry.notchWidth,
                earWidth: layout.earWidth,
                onTap: { services.media.openCurrentSource() }
            )
        case .agentLive:
            AgentLiveView(
                sessions: state.visibleAgentSessions,
                notchWidth: state.geometry.notchWidth,
                earWidth: layout.earWidth
            )
        case .calendarCountdown:
            if let event = state.nextCalendarEvent {
                CalendarCountdownView(
                    event: event,
                    notchWidth: state.geometry.notchWidth,
                    earWidth: layout.earWidth,
                    onTap: { services.calendar.openEvent(event) }
                )
            }
        case .privacyIndicator:
            PrivacyIndicatorCompactView(
                status: state.privacyStatus,
                notchWidth: state.geometry.notchWidth,
                earWidth: layout.earWidth
            )
        case .peek:
            if let activity = state.currentActivity {
                ActivityPeekView(activity: activity, notchWidth: state.geometry.notchWidth)
            }
        case .volumeHUD:
            if let hud = state.volumeHUD {
                VolumeHUDView(hud: hud, notchWidth: state.geometry.notchWidth)
            }
        case .expanded:
            ExpandedView(state: state, services: services)
        }
    }
}
