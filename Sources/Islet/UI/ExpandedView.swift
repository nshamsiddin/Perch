import SwiftUI

/// The island panel shown on hover: now-playing controls plus battery status.
struct ExpandedView: View {
    @ObservedObject var state: IslandState
    let services: AppServices
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = IslandTheme(scheme: colorScheme)
        return VStack(spacing: 0) {
            // Reserve the notch strip so content never sits behind the camera housing.
            Color.clear.frame(height: state.geometry.notchHeight)

            HStack(alignment: .center, spacing: 12) {
                MediaView(state: state, services: services, theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BatteryView(state: state, theme: theme)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
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

    var body: some View {
        if state.battery.hasBattery {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                Text("\(max(state.battery.percentage, 0))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
            }
            .padding(.horizontal, 9)
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
