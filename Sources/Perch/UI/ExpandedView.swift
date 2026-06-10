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
            // The reserved notch strip doubles as the agents header: the "Agents" title sits on the
            // left ear (where the date used to be) and the status pills on the right ear (where the
            // clock used to be), flanking the camera housing via a center spacer of notchWidth.
            AgentsNotchHeaderView(sessions: state.visibleAgentSessions,
                                  notchWidth: state.geometry.notchWidth,
                                  theme: theme)
                .frame(height: state.geometry.notchHeight)

            // Agent session rows lead the panel body, directly under their header in the strip.
            if state.hasActiveAgents {
                VStack(spacing: 0) {
                    Color.clear.frame(height: layout.agentsSectionTopInset)
                    AgentsSectionView(sessions: state.visibleAgentSessions, theme: theme,
                                      layout: layout,
                                      showsHeader: false,
                                      controlEnabled: state.agentsControlActive,
                                      onFocus: { services.focusAgent($0) },
                                      onApprove: { services.approveAgent($0, note: $1) },
                                      onDeny: { services.denyAgent($0) },
                                      onStop: { services.stopAgent($0) })
                }
                .transition(.opacity)
            }

            // Now-playing / battery row sits below the agents overview. A hairline divider
            // separates it from the agents list above; with no agents it simply leads the panel.
            if state.showsContentRow {
                if state.hasActiveAgents {
                    Rectangle()
                        .fill(theme.panelStroke)
                        .frame(height: 0.5)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
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

// MARK: - Notch header (agents)

/// Header occupying the reserved notch strip in the expanded panel. The "Agents" identity sits on
/// the left ear and the working/waiting status pills on the right ear, with a `notchWidth` center
/// spacer so neither slides behind the camera housing. Renders nothing while no agents are active.
private struct AgentsNotchHeaderView: View {
    let sessions: [AgentSession]
    let notchWidth: CGFloat
    let theme: IslandTheme

    private var workingCount: Int { sessions.lazy.filter(\.isWorking).count }
    private var waitingCount: Int { sessions.lazy.filter(\.isWaiting).count }

    /// Working sessions that haven't pinged in a while read as "stuck" (likely wedged mid-tool-call),
    /// matching `AgentRowView`'s per-row threshold so the header summary agrees with the rows.
    private func stuckCount(now: Date) -> Int {
        sessions.lazy.filter {
            $0.isWorking && now.timeIntervalSince($0.updatedAt) >= Double(AgentRowView.stuckThreshold)
        }.count
    }

    var body: some View {
        // A slow tick keeps the stuck count current (staleness depends on wall-clock time, not on
        // any republish from the status service).
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 0) {
                if !sessions.isEmpty {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                        Text("Agents")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(width: notchWidth)

                    HStack(spacing: 6) {
                        if stuckCount(now: context.date) > 0 {
                            StuckChip(count: stuckCount(now: context.date))
                        }
                        AgentStatusPills(waitingCount: waitingCount, workingCount: workingCount)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// A stuck-agent indicator for the header: an amber warning glyph + count, distinct from the
/// orange "waiting" dot so a wedged run (working but quiet too long) stands apart from one that's
/// intentionally awaiting input.
private struct StuckChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.14)))
    }
}

// MARK: - Now Playing

private struct MediaView: View {
    @ObservedObject var state: IslandState
    let services: AppServices
    let theme: IslandTheme

    var body: some View {
        if state.nowPlaying.hasContent {
            playingRow
        } else {
            // Idle: the whole cell is a single affordance to launch Spotify, led by the white
            // Spotify mark in the tile.
            Button { services.media.launchSpotify() } label: { idleRow }
                .buttonStyle(.plain)
                .help("Open Spotify")
        }
    }

    private var playingRow: some View {
        HStack(spacing: 10) {
            // Tapping the art + title jumps to the app playing it (Spotify / Music). The transport
            // controls stay separate so their own taps don't trigger the open.
            Button { services.media.openCurrentSource() } label: {
                HStack(spacing: 10) {
                    artworkTile

                    // Only the title/artist column flexes, so it absorbs slack and truncates long
                    // titles — keeping the transport controls at a stable x-position.
                    VStack(alignment: .leading, spacing: 2) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(openSourceHelp)

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

    private var artworkTile: some View {
        ZStack {
            if let artwork = state.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.tileFill)
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.85))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var openSourceHelp: String {
        let source = state.nowPlaying.source
        return source.isEmpty ? "Open player" : "Open \(source)"
    }

    /// The installed Spotify app's real icon, read once. Nil when Spotify isn't installed, in which
    /// case the idle tile falls back to the drawn brand mark.
    private static let spotifyAppIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MediaService.spotifyBundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()

    private var idleRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.tileFill)
                if let icon = Self.spotifyAppIcon {
                    // The real Spotify app icon, so the affordance unmistakably reads as Spotify.
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                } else {
                    // Brand-green Spotify mark when the app isn't installed to read an icon from.
                    SpotifyLogoView(size: 26)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Text("Open Spotify")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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

// MARK: - Spotify logo

/// The Spotify brand mark drawn as a vector: the green disc with three upward-bowing "sound wave"
/// arcs. Self-contained (no asset needed) and crisp at any size.
private struct SpotifyLogoView: View {
    var size: CGFloat = 30
    /// The disc color (brand green by default; white for the monochrome mark).
    var discColor: Color = Color(red: 0.114, green: 0.725, blue: 0.329) // #1DB954
    /// The wave color — on the green mark it's near-black; on the white mark it matches the
    /// backing tile so the waves read as cut-out negative space.
    var waveColor: Color = Color.black.opacity(0.9)

    var body: some View {
        ZStack {
            Circle().fill(discColor)
            SpotifyWaves()
                .stroke(waveColor,
                        style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Open Spotify")
    }
}

/// Three stacked upward-bowing arcs approximating Spotify's waves, sized to the given rect.
private struct SpotifyWaves: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func bow(y: CGFloat, inset: CGFloat, controlY: CGFloat) {
            let left = CGPoint(x: rect.minX + w * inset, y: rect.minY + h * y)
            let right = CGPoint(x: rect.maxX - w * inset, y: rect.minY + h * y)
            let control = CGPoint(x: rect.midX, y: rect.minY + h * controlY)
            path.move(to: left)
            path.addQuadCurve(to: right, control: control)
        }
        bow(y: 0.42, inset: 0.18, controlY: 0.26)
        bow(y: 0.57, inset: 0.26, controlY: 0.44)
        bow(y: 0.71, inset: 0.34, controlY: 0.60)
        return path
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
