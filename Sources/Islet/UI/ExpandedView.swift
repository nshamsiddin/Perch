import SwiftUI

/// The island panel shown on hover: now-playing controls plus battery status.
struct ExpandedView: View {
    @ObservedObject var state: IslandState
    let services: AppServices
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = IslandTheme(scheme: colorScheme)
        let layout = IslandLayout(geometry: state.geometry,
                                  mediaEnabled: state.mediaEnabled,
                                  batteryEnabled: state.batteryEnabled)
        return VStack(spacing: 0) {
            // The reserved notch strip doubles as a glanceable header: date and live time flank
            // the camera housing (a center spacer of notchWidth keeps content clear of it), filling
            // the otherwise-dead "ears" with feature-independent info — like the menu bar it sits under.
            NotchHeaderView(notchWidth: state.geometry.notchWidth, theme: theme)
                .frame(height: state.geometry.notchHeight)

            // Top row: full now-playing cell when media is on; a slim battery-only strip otherwise;
            // nothing when both features are off. Height comes from the layout so the strip is
            // compact (the chip never floats in an oversized media-sized void).
            if state.showsContentRow {
                HStack(alignment: .center, spacing: 12) {
                    if state.mediaEnabled {
                        MediaView(state: state, services: services, theme: theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                    BatteryView(state: state, theme: theme, layout: layout)
                }
                .frame(maxWidth: .infinity)
                .frame(height: layout.contentRowHeight)
            }

            // Agent overview appears only while agents are active. The hairline divider is only
            // drawn when a content row sits above it — otherwise it would be an orphaned separator
            // hugging the notch, so we use plain breathing room instead.
            if state.hasActiveAgents {
                VStack(spacing: 0) {
                    if state.showsContentRow {
                        Rectangle()
                            .fill(theme.panelStroke)
                            .frame(height: 0.5)
                            .frame(height: layout.agentsSectionTopInset, alignment: .center)
                    } else {
                        Color.clear.frame(height: layout.agentsSectionTopInset)
                    }
                    AgentsSectionView(sessions: state.visibleAgentSessions, theme: theme,
                                      layout: layout, onFocus: { services.focusAgent($0) })
                }
                .transition(.opacity)
            }

            // Idle state: every feature is off and nothing is active. Rather than an empty sheet,
            // show a quiet line that tells the user how to bring the island back to life.
            if !state.showsContentRow && !state.hasActiveAgents {
                idleRow(theme: theme)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.idleRowHeight)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func idleRow(theme: IslandTheme) -> some View {
        VStack(spacing: 3) {
            Text("Nothing to show")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Text("Turn on a feature from the menu bar")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.tertiaryText)
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - Notch header

/// Slim header occupying the reserved notch strip in the expanded panel. Date sits on the left
/// ear and a live clock on the right, with a `notchWidth` center spacer so neither slides behind
/// the camera housing. Stays quiet (secondary text) so it frames the content without competing.
private struct NotchHeaderView: View {
    let notchWidth: CGFloat
    let theme: IslandTheme

    var body: some View {
        // Re-render on the minute boundary so the clock stays current without a per-second tick.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            HStack(spacing: 0) {
                Text(Self.dateString(now))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: notchWidth)
                Text(Self.timeString(now))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 4)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    private static func dateString(_ date: Date) -> String { dateFormatter.string(from: date) }
    private static func timeString(_ date: Date) -> String { timeFormatter.string(from: date) }
}

// MARK: - Now Playing

private struct MediaView: View {
    @ObservedObject var state: IslandState
    let services: AppServices
    let theme: IslandTheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let artwork = state.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.tileFill)
                    Image(systemName: state.nowPlaying.hasContent ? "music.note" : "music.note.list")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText.opacity(0.85))
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Only the title/artist column flexes, so it absorbs slack and truncates long
            // titles — keeping the transport controls at a stable x-position.
            VStack(alignment: .leading, spacing: 2) {
                if state.nowPlaying.hasContent {
                    Text(state.nowPlaying.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(state.nowPlaying.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Nothing playing")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                    Text("Music or Spotify")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.nowPlaying.hasContent {
                HStack(spacing: 6) {
                    transportButton("backward.fill") { services.media.previous() }
                    transportButton(state.nowPlaying.isPlaying ? "pause.fill" : "play.fill") {
                        services.media.playPause()
                    }
                    transportButton("forward.fill") { services.media.next() }
                }
                .fixedSize()
                .layoutPriority(1)
            }
        }
    }

    private func transportButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.controlIcon)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.controlFill))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Battery

private struct BatteryView: View {
    @ObservedObject var state: IslandState
    let theme: IslandTheme
    let layout: IslandLayout

    var body: some View {
        if state.batteryActive {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                Text("\(max(state.battery.percentage, 0))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
            }
            .padding(.horizontal, layout.chipHorizontalPadding)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.controlFill))
        }
    }

    private var symbol: String {
        if state.battery.isCharging { return "battery.100.bolt" }
        switch state.battery.percentage {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var tint: Color {
        if state.battery.isCharging { return .green }
        return state.battery.percentage < 15 ? .red : theme.neutralTint
    }
}
