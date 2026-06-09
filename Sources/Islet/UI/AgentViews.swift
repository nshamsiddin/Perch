import SwiftUI

// MARK: - Tool icons

/// The official Cursor brand mark (the "cube"), transcribed from Cursor's published logo SVG
/// (viewBox 49×56). Drawn as a vector so it stays crisp at any size and tints to any color. The
/// outer cube and the inner triangle are filled even-odd, carving the cube's signature hollow.
struct CursorLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let vbW: CGFloat = 49, vbH: CGFloat = 56
        let scale = min(rect.width / vbW, rect.height / vbH)
        let ox = rect.minX + (rect.width - vbW * scale) / 2
        let oy = rect.minY + (rect.height - vbH * scale) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }

        var path = Path()
        // Outer cube silhouette.
        path.move(to: p(48.0226, 13.2547))
        path.addLine(to: p(25.6601, 0.311786))
        path.addCurve(to: p(23.3378, 0.311786), control1: p(24.942, -0.103929), control2: p(24.0559, -0.103929))
        path.addLine(to: p(0.976347, 13.2547))
        path.addCurve(to: p(0, 14.9502), control1: p(0.372691, 13.6041), control2: p(0, 14.2503))
        path.addLine(to: p(0, 41.0498))
        path.addCurve(to: p(0.976347, 42.7453), control1: p(0, 41.7496), control2: p(0.372691, 42.3958))
        path.addLine(to: p(23.3389, 55.6882))
        path.addCurve(to: p(25.6611, 55.6882), control1: p(24.057, 56.1039), control2: p(24.943, 56.1039))
        path.addLine(to: p(48.0237, 42.7453))
        path.addCurve(to: p(49, 41.0498), control1: p(48.6273, 42.3958), control2: p(49, 41.7496))
        path.addLine(to: p(49, 14.9502))
        path.addCurve(to: p(48.0237, 13.2547), control1: p(49, 14.2503), control2: p(48.6273, 13.6041))
        path.addLine(to: p(48.0226, 13.2547))
        path.closeSubpath()
        // Inner hollow.
        path.move(to: p(46.6179, 15.9964))
        path.addLine(to: p(25.0302, 53.4802))
        path.addCurve(to: p(24.4989, 53.337), control1: p(24.8842, 53.7328), control2: p(24.4989, 53.6296))
        path.addLine(to: p(24.4989, 28.793))
        path.addCurve(to: p(23.8134, 27.6027), control1: p(24.4989, 28.3026), control2: p(24.2375, 27.849))
        path.addLine(to: p(2.61094, 15.3312))
        path.addCurve(to: p(2.75372, 14.7987), control1: p(2.35898, 15.1849), control2: p(2.46186, 14.7987))
        path.addLine(to: p(45.9292, 14.7987))
        path.addCurve(to: p(46.619, 15.9974), control1: p(46.5423, 14.7987), control2: p(46.9255, 15.4649))
        path.addLine(to: p(46.6179, 15.9964))
        path.closeSubpath()
        return path
    }
}

/// Renders an agent tool's glyph: an SF Symbol for Claude Code, the vector brand cube for Cursor.
/// Sized by `size` (the equivalent SF font point size) and tinted with `color`, so both tools sit
/// on the same visual rail regardless of which one a row belongs to.
struct AgentToolIcon: View {
    let tool: AgentTool
    var size: CGFloat = 12
    var weight: Font.Weight = .semibold
    let color: Color

    var body: some View {
        switch tool {
        case .claudeCode:
            Image(systemName: tool.symbol)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
        case .cursor:
            CursorLogoShape()
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: size + 1, height: size + 1)
        }
    }
}

// MARK: - Collapsed live indicator

/// Collapsed "AI agents working" presentation: tool glyph(s) on the left ear and an animated
/// thinking pulse (+ count) on the right ear, flanking the notch via the same
/// center-spacer-of-`notchWidth` pattern as `NowPlayingCompactView`. Stays dark to blend with the
/// physical notch; the pulse turns amber when any session is waiting for input.
struct AgentLiveView: View {
    let sessions: [AgentSession]
    let notchWidth: CGFloat
    let earWidth: CGFloat

    private var tools: [AgentTool] {
        [.claudeCode, .cursor].filter { tool in sessions.contains { $0.tool == tool } }
    }
    private var anyWaiting: Bool { sessions.contains { $0.isWaiting } }
    private var accent: Color { anyWaiting ? .orange : .white }

    var body: some View {
        HStack(spacing: 0) {
            leftEar.frame(width: earWidth)
            Spacer().frame(width: notchWidth)
            rightEar.frame(width: earWidth)
        }
    }

    /// Tool glyph(s), nudged toward the notch.
    private var leftEar: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            ForEach(tools, id: \.self) { tool in
                AgentToolIcon(tool: tool, size: 12, color: .white)
            }
        }
        .padding(.trailing, 7)
    }

    /// Animated thinking pulse + a count badge when more than one session is active.
    private var rightEar: some View {
        HStack(spacing: 5) {
            AgentPulseView(accent: accent, paused: anyWaiting)
            if sessions.count > 1 {
                Text("\(sessions.count)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
    }
}

/// Working: three dots that breathe out of phase to read as "thinking". Waiting: the dots give
/// way to a single pulsing exclamation glyph so "needs your input" actively draws the eye rather
/// than fading into a quiet steady state.
struct AgentPulseView: View {
    let accent: Color
    var paused: Bool = false
    @State private var animating = false

    var body: some View {
        Group {
            if paused {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(accent)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                               value: animating)
            } else {
                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(accent)
                            .frame(width: 4, height: 4)
                            .opacity(animating ? 1.0 : 0.25)
                            .animation(.easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                                value: animating)
                    }
                }
            }
        }
        .frame(height: 14)
        .onAppear { animating = true }
    }
}

// MARK: - Expanded panel section

/// Agent overview shown in the expanded panel. Deliberately label-free — no "AI Agents" title —
/// so it reads as a clean status surface: a slim summary line (working / waiting counts) above up
/// to a few session rows, each keyed by project with a live elapsed time. Sessions waiting on the
/// user float to the top so the actionable ones are always in view. Overflow collapses into a
/// "+N more" line. Uses the shared `IslandLayout` metrics with fixed row heights so it matches the
/// panel's reserved height.
struct AgentsSectionView: View {
    let sessions: [AgentSession]
    let theme: IslandTheme
    let layout: IslandLayout
    /// Invoked when a row is clicked, to refocus that agent's terminal tab / editor window.
    var onFocus: (AgentSession) -> Void = { _ in }

    /// Waiting sessions first (they need attention), preserving the upstream order otherwise.
    private var ordered: [AgentSession] {
        sessions.filter(\.isWaiting) + sessions.filter { !$0.isWaiting }
    }
    private var workingCount: Int { sessions.lazy.filter(\.isWorking).count }
    private var waitingCount: Int { sessions.lazy.filter(\.isWaiting).count }

    var body: some View {
        // One shared clock drives every row's relative time, so "2m" ticks up live without the
        // status service having to republish (the underlying mtime doesn't change while idle).
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 0) {
                summary
                    .frame(height: layout.agentsHeaderHeight)
                ForEach(ordered.prefix(layout.agentsRowsMax)) { session in
                    AgentRowView(session: session, now: now, theme: theme, onTap: onFocus)
                        .frame(height: layout.agentRowHeight)
                }
                if sessions.count > layout.agentsRowsMax {
                    Text("+\(sessions.count - layout.agentsRowsMax) more")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(height: layout.agentsMoreLineHeight, alignment: .leading)
                        .padding(.leading, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Inset the right-aligned status text so it lines up with the battery chip's text (which
        // sits chipHorizontalPadding in from the panel edge).
        .padding(.trailing, layout.chipHorizontalPadding)
    }

    /// Section header. Mirrors a row's geometry exactly — a glyph in the 18pt icon rail, then a
    /// title on the same baseline column as the project names below — so the list reads as a single
    /// aligned unit. The sparkles mark + a real title ("Agents") establish the section as AI agents;
    /// soft tinted state badges sit on the trailing edge, stacked over each row's status badge.
    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 18)

            Text("Agents")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if waitingCount > 0 { countChip(color: .orange, count: waitingCount, label: "waiting") }
                if workingCount > 0 { countChip(color: .green, count: workingCount, label: "working") }
            }
            .padding(.trailing, 6)
        }
        .padding(.leading, 6)
    }

    /// A soft tinted capsule pairing a state dot with its count + label — Apple's "status pill"
    /// idiom, legible at a glance without shouting.
    private func countChip(color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// A single agent session row: tool glyph, project (primary) + live activity, and a status badge.
/// The whole row is a button that refocuses the owning terminal tab / editor window.
struct AgentRowView: View {
    let session: AgentSession
    let now: Date
    let theme: IslandTheme
    var onTap: (AgentSession) -> Void = { _ in }
    @State private var hovering = false

    /// Seconds since the last hook event. A working session that hasn't pinged in a while is
    /// likely mid-long-tool-call — surfaced as "stuck" so a wedged agent stands out.
    private var staleSeconds: Int { max(0, Int(now.timeIntervalSince(session.updatedAt))) }
    private var isStuck: Bool { session.isWorking && staleSeconds >= Self.stuckThreshold }

    /// Subtitle prefers the live activity ("Editing Foo.swift"); the glyph already names the tool,
    /// so we fall back to the tool label only when there's no activity to show.
    private var subtitle: String { session.activity ?? session.tool.label }

    var body: some View {
        Button { onTap(session) } label: {
            HStack(spacing: 8) {
                // Tint the glyph amber when this session is waiting on the user.
                AgentToolIcon(tool: session.tool, size: 12,
                              color: session.isWaiting ? Color.orange : theme.primaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    // Project leads: it's the identifier you scan for when juggling agents.
                    Text(session.project)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AgentStatusBadge(state: session.state,
                                 age: Self.shortAge(of: session.updatedAt, now: now),
                                 stuck: isStuck,
                                 theme: theme)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.controlFill.opacity(hovering ? 1 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// Seconds without a hook event before a working session reads as stuck.
    static let stuckThreshold = 60

    /// Compact, calendar-free elapsed time ("now", "8s", "3m", "2h", "1d").
    static func shortAge(of date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<5:        return "now"
        case ..<60:       return "\(seconds)s"
        case ..<3600:     return "\(seconds / 60)m"
        case ..<86_400:   return "\(seconds / 3600)h"
        default:          return "\(seconds / 86_400)d"
        }
    }
}

/// A small colored dot conveying run state, paired with elapsed time. Waiting rows keep the word
/// so they stand out; working rows stay quiet — just the dot and how long they've been running.
/// A working session that's gone quiet too long ("stuck") flips its dot + time to amber.
struct AgentStatusBadge: View {
    let state: AgentRunState
    let age: String
    var stuck: Bool = false
    let theme: IslandTheme

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if state == .waiting {
                Text("Waiting")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(age)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ageColor)
        }
    }

    private var color: Color {
        if state == .waiting { return .orange }
        return stuck ? .orange : .green
    }

    private var ageColor: Color {
        if state == .waiting { return color.opacity(0.8) }
        return stuck ? .orange : theme.tertiaryText
    }
}
