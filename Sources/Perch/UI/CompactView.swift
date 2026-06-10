import SwiftUI

/// Transient peek shown just under/around the notch when a live activity fires.
/// Content flanks the camera housing via a center spacer matching the notch width.
struct ActivityPeekView: View {
    let activity: Activity
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: activity.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(width: notchWidth)

            Text(activity.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 10)
    }
}

/// Transient output-volume HUD: a speaker glyph on the left ear and a level bar on the right ear,
/// flanking the notch via the same center-spacer-of-notchWidth pattern. Stays dark in both
/// appearances to blend with the physical notch.
struct VolumeHUDView: View {
    let hud: VolumeHUD
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hud.muted ? Color.red.opacity(0.95) : .white)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.18), value: symbolName)

            Spacer().frame(width: notchWidth)

            levelBar
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
    }

    private var symbolName: String {
        if hud.muted { return "speaker.slash.fill" }
        switch hud.level {
        case ..<0.001: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private var fillFraction: CGFloat {
        hud.muted ? 0 : CGFloat(min(1, max(0, hud.level)))
    }

    private var levelBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(hud.muted ? Color.red.opacity(0.28) : Color.white.opacity(0.18))
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: max(0, proxy.size.width * fillFraction))
            }
        }
        .frame(height: 4)
        .animation(.easeInOut(duration: 0.18), value: fillFraction)
        .animation(.easeInOut(duration: 0.18), value: hud.muted)
    }
}

/// Collapsed now-playing presentation: a left art/glyph ear and a right equalizer ear flanking
/// the notch. Uses the same center-spacer-of-notchWidth pattern as `ActivityPeekView` so nothing
/// sits behind the camera. Stays dark in both appearances to blend with the physical notch.
struct NowPlayingCompactView: View {
    let nowPlaying: NowPlaying
    let artwork: NSImage?
    let notchWidth: CGFloat
    let earWidth: CGFloat
    /// Opens the app that owns the current track (Spotify / Music).
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                leftEar
                    .frame(width: earWidth)

                Spacer().frame(width: notchWidth)

                rightEar
                    .frame(width: earWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(nowPlaying.source.isEmpty ? "Open player" : "Open \(nowPlaying.source)")
    }

    /// Album-art thumbnail when available, else a small music glyph; nudged toward the notch.
    private var leftEar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 21, height: 21)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 21, height: 21)
                }
            }
        }
        .padding(.trailing, 7)
    }

    /// Animated equalizer when playing; static low bars when paused.
    private var rightEar: some View {
        HStack(spacing: 0) {
            EqualizerView(isPlaying: nowPlaying.isPlaying)
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
    }
}

/// A small equalizer: vertical bars that oscillate while playing using a per-bar
/// repeating spring/ease so they fall out of phase, and rest at low static heights when paused.
struct EqualizerView: View {
    let isPlaying: Bool
    @State private var animating = false

    private let maxHeights: [CGFloat] = [11, 17, 8, 14]
    private let minHeights: [CGFloat] = [4, 6, 3, 5]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(maxHeights.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 2.5, height: height(at: index))
                    .animation(animation(at: index), value: animating)
            }
        }
        .frame(height: 18, alignment: .center)
        .onAppear { animating = true }
        .onChange(of: isPlaying) { playing in
            // Restart the repeating animation when resuming playback.
            if playing {
                animating = false
                DispatchQueue.main.async { animating = true }
            }
        }
    }

    private func height(at index: Int) -> CGFloat {
        guard isPlaying else { return minHeights[index] }
        return animating ? maxHeights[index] : minHeights[index]
    }

    private func animation(at index: Int) -> Animation? {
        guard isPlaying else { return .easeInOut(duration: 0.25) }
        return .easeInOut(duration: 0.42 + Double(index) * 0.08).repeatForever(autoreverses: true)
    }
}

/// Live clock flanking the notch when the clock widget is enabled and nothing else is showing.
struct ClockCompactView: View {
    let notchWidth: CGFloat
    let earWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: earWidth, alignment: .trailing)
            }
            Spacer().frame(width: notchWidth)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: earWidth, alignment: .leading)
            }
        }
    }
}

/// Countdown to the next calendar event within 30 minutes.
struct CalendarCountdownView: View {
    let event: CalendarEvent
    let notchWidth: CGFloat
    let earWidth: CGFloat
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: earWidth)
                Spacer().frame(width: notchWidth)
                Text(countdownLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: earWidth)
            }
        }
        .buttonStyle(.plain)
    }

    private var countdownLabel: String {
        let minutes = CalendarService.minutesUntil(event.start)
        if minutes == 0 { return "Now" }
        return "\(minutes)m"
    }
}

/// Privacy indicator ears when camera, mic, or screen capture is active.
struct PrivacyIndicatorCompactView: View {
    let status: PrivacyStatus
    let notchWidth: CGFloat
    let earWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if status.cameraActive {
                    indicatorDot(color: .green, symbol: "camera.fill")
                }
                if status.micActive {
                    indicatorDot(color: .orange, symbol: "mic.fill")
                }
            }
            .frame(width: earWidth)
            Spacer().frame(width: notchWidth)
            HStack(spacing: 4) {
                if status.screenCaptureActive {
                    indicatorDot(color: .red, symbol: "rectangle.inset.filled.and.person.filled")
                }
            }
            .frame(width: earWidth)
        }
    }

    private func indicatorDot(color: Color, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
    }
}
