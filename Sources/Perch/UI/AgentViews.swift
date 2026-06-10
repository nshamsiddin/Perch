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
    /// Every tracked session has finished its turn — show a settled check rather than a pulse.
    private var allDone: Bool { !sessions.isEmpty && sessions.allSatisfy(\.isDone) }

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

    /// Animated thinking pulse + a count badge when more than one session is active; a settled
    /// green check once every session has finished.
    private var rightEar: some View {
        HStack(spacing: 5) {
            if allDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                AgentPulseView(accent: accent, paused: anyWaiting)
            }
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
    /// Whether the inline "Agents" title + status pills header is drawn. Off when that header has
    /// been hoisted into the notch strip up top, leaving this section to render just the rows.
    var showsHeader: Bool = true
    /// Whether the inline control affordances (Approve/Deny/Stop) are shown.
    var controlEnabled: Bool = false
    /// Invoked when a row is clicked, to refocus that agent's terminal tab / editor window.
    var onFocus: (AgentSession) -> Void = { _ in }
    /// Approve a pending tool call, with an optional steering note.
    var onApprove: (AgentSession, String?) -> Void = { _, _ in }
    /// Deny a pending tool call.
    var onDeny: (AgentSession) -> Void = { _ in }
    /// Best-effort stop of a running agent.
    var onStop: (AgentSession) -> Void = { _ in }
    /// Whether gating is currently snoozed (shown as a subtle header chip).
    var gatingPaused: Bool = false

    @State private var overflowExpanded = false

    /// Waiting sessions first (they need attention), just-finished sessions last (they're winding
    /// down), working sessions in between — preserving the upstream order within each group.
    private var ordered: [AgentSession] {
        sessions.filter(\.isWaiting)
            + sessions.filter { !$0.isWaiting && !$0.isDone }
            + sessions.filter(\.isDone)
    }
    private var workingCount: Int { sessions.lazy.filter(\.isWorking).count }
    private var waitingCount: Int { sessions.lazy.filter(\.isWaiting).count }
    private var overflowCount: Int { max(0, sessions.count - layout.agentsRowsMax) }
    private var visibleSessions: [AgentSession] {
        overflowExpanded ? ordered : Array(ordered.prefix(layout.agentsRowsMax))
    }

    var body: some View {
        // One shared clock drives every row's relative time, so "2m" ticks up live without the
        // status service having to republish (the underlying mtime doesn't change while idle).
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 0) {
                if showsHeader {
                    summary
                        .frame(height: layout.agentsHeaderHeight)
                }
                if overflowExpanded && overflowCount > 0 {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleSessions) { session in
                                agentRow(session: session, now: now)
                            }
                        }
                    }
                    .frame(maxHeight: layout.agentsOverflowScrollMaxHeight)
                } else {
                    ForEach(visibleSessions) { session in
                        agentRow(session: session, now: now)
                    }
                }
                if overflowCount > 0 {
                    overflowToggle
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Inset the right-aligned status text so it lines up with the battery chip's text (which
        // sits chipHorizontalPadding in from the panel edge).
        .padding(.trailing, layout.chipHorizontalPadding)
    }

    @ViewBuilder
    private func agentRow(session: AgentSession, now: Date) -> some View {
        AgentRowView(session: session, now: now, theme: theme,
                     controlEnabled: controlEnabled,
                     onTap: onFocus, onApprove: onApprove,
                     onDeny: onDeny, onStop: onStop)
            .frame(height: session.isAwaitingApproval
                   ? layout.agentApprovalRowHeight : layout.agentRowHeight)
    }

    private var overflowToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { overflowExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: overflowExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Text(overflowExpanded ? "Show less" : "+\(overflowCount) more")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(theme.secondaryText)
            .frame(height: layout.agentsMoreLineHeight, alignment: .leading)
            .padding(.leading, 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

            if gatingPaused {
                GatingPausedChip()
            }
            AgentStatusPills(waitingCount: waitingCount, workingCount: workingCount)
                .padding(.trailing, 6)
        }
        .padding(.leading, 6)
    }
}

/// Subtle chip shown while gating is snoozed — agents proceed without island approval.
struct GatingPausedChip: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Paused")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

/// The working/waiting status pills, shared by the in-panel agents header and the notch-strip
/// header. Renders nothing when no session is in either state.
///
/// Adaptive density: with a single active state there's room for the descriptive label
/// ("1 waiting"); when both states are present they'd overflow the narrow notch ear, so the chips
/// collapse to compact color-coded counts — the amber/green coding (and the rows below) keeps them
/// unambiguous without truncating.
struct AgentStatusPills: View {
    let waitingCount: Int
    let workingCount: Int

    private var compact: Bool { waitingCount > 0 && workingCount > 0 }

    var body: some View {
        HStack(spacing: 6) {
            if waitingCount > 0 {
                AgentCountChip(color: .orange, count: waitingCount,
                               label: compact ? nil : "waiting")
            }
            if workingCount > 0 {
                AgentCountChip(color: .green, count: workingCount,
                               label: compact ? nil : "working", animated: true)
            }
        }
    }
}

/// A soft tinted capsule pairing a state dot with its count — Apple's "status pill" idiom, legible
/// at a glance without shouting. With a `label` it spells out the state ("1 waiting"); without one
/// it stays compact (just the dot + count) so several can share a tight row.
struct AgentCountChip: View {
    let color: Color
    let count: Int
    var label: String? = nil
    /// Working chips carry the live beacon; waiting chips stay a quiet static dot.
    var animated: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if animated {
                WorkingDot(color: color, size: 6)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(label.map { "\(count) \($0)" } ?? "\(count)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// The "actively working" beacon that replaces the static green dot wherever a session is running:
/// a steady green core emitting soft rings that swell outward and fade. It borrows Apple's live /
/// locating idiom (Find My's pulsing pin, AirDrop's radar) to say "this agent is transmitting right
/// now" without shouting. Only scale + opacity animate — GPU-cheap and smooth — and the rings draw
/// *outside* the core's fixed frame, so the beacon occupies exactly the footprint of the dot it
/// replaces and never nudges the surrounding layout. Two rings ride half a period out of phase so
/// the emission stays continuous instead of pulsing with a visible gap between cycles.
struct WorkingDot: View {
    var color: Color = .green
    var size: CGFloat = 6
    @State private var animating = false

    private static let period = 1.8

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { ring in
                Circle()
                    .stroke(color, lineWidth: 1)
                    .scaleEffect(animating ? 2.6 : 1)
                    .opacity(animating ? 0 : 0.5)
                    .animation(.easeOut(duration: Self.period)
                        .repeatForever(autoreverses: false)
                        .delay(Double(ring) * Self.period / 2),
                        value: animating)
            }
            Circle()
                .fill(color)
                // A soft constant glow gives the core presence between ripples, so the dot itself
                // reads as alive rather than a flat disc waiting for the next ring.
                .shadow(color: color.opacity(0.6), radius: 1.5)
        }
        .frame(width: size, height: size)
        .onAppear { animating = true }
    }
}

/// A single agent session row: tool glyph, project (primary) + live activity, and a status badge.
/// The whole row is a button that refocuses the owning terminal tab / editor window.
struct AgentRowView: View {
    let session: AgentSession
    let now: Date
    let theme: IslandTheme
    var controlEnabled: Bool = false
    var onTap: (AgentSession) -> Void = { _ in }
    var onApprove: (AgentSession, String?) -> Void = { _, _ in }
    var onDeny: (AgentSession) -> Void = { _ in }
    var onStop: (AgentSession) -> Void = { _ in }
    @State private var hovering = false
    /// Optional steering note typed alongside an Approve; cleared after the row stops pending.
    @State private var note: String = ""

    /// Seconds since the last hook event. A working session that hasn't pinged in a while is
    /// likely mid-long-tool-call — surfaced as "stuck" so a wedged agent stands out.
    private var staleSeconds: Int { max(0, Int(now.timeIntervalSince(session.updatedAt))) }
    private var isStuck: Bool { session.isWorking && staleSeconds >= Self.stuckThreshold }

    /// Subtitle prefers the live activity ("Editing Foo.swift"); the glyph already names the tool,
    /// so we fall back to the tool label only when there's no activity to show. A finished session
    /// reads "Finished" since it has no live activity.
    private var subtitle: String {
        if session.isDone { return "Finished" }
        return session.activity ?? session.tool.label
    }

    /// Secondary detail revealed on hover: the model and (if known) the latest-turn token count —
    /// power info kept off the resting glance surface so rows stay calm.
    private var hoverDetail: String? {
        guard let model = session.model else { return nil }
        if let tokens = session.tokens { return "\(model) · \(Self.shortTokens(tokens))" }
        return model
    }

    /// Stop is offered on active rows that aren't already asking for an explicit decision.
    private var showsStop: Bool {
        controlEnabled && !session.isAwaitingApproval && (session.isWorking || session.isWaiting)
    }

    var body: some View {
        VStack(spacing: 5) {
            topRow
            if session.isAwaitingApproval { approvalActions }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.controlFill.opacity(hovering ? 1 : 0))
        )
        .onHover { hovering = $0 }
    }

    /// Tool glyph + project/activity (a focus button), with the Stop pill and status badge as
    /// siblings so they don't nest inside the focus button.
    private var topRow: some View {
        HStack(spacing: 8) {
            Button { onTap(session) } label: {
                HStack(spacing: 8) {
                    // Tint the glyph amber when this session is waiting on the user.
                    AgentToolIcon(tool: session.tool, size: 12,
                                  color: session.isWaiting ? Color.orange : theme.primaryText)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        // Project leads: it's the identifier you scan for when juggling agents. The
                        // branch tag rides alongside so worktrees of one repo are distinguishable.
                        HStack(spacing: 6) {
                            Text(session.project)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .layoutPriority(1)
                            if let branch = session.branch {
                                BranchTag(branch: branch, theme: theme)
                            }
                        }
                        Text(hovering ? (hoverDetail ?? subtitle) : subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsStop { stopButton }

            AgentStatusBadge(state: session.state,
                             age: Self.shortAge(of: session.updatedAt, now: now),
                             stuck: isStuck,
                             theme: theme)
        }
    }

    /// Second line for a pending approval: an optional steering note, then Deny / Approve. Aligned
    /// under the project name (past the 18pt icon rail + 8pt gap) so it reads as part of the row.
    private var approvalActions: some View {
        HStack(spacing: 6) {
            TextField("Note (optional)", text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.controlFill))
                .frame(maxWidth: .infinity)

            pillButton(title: "Deny", tint: .red) { onDeny(session) }
            pillButton(title: "Approve", tint: .green) {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onApprove(session, trimmed.isEmpty ? nil : trimmed)
            }
        }
        .padding(.leading, 26)
    }

    private var stopButton: some View {
        Button { onStop(session) } label: {
            Text("Stop")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }

    private func pillButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    /// Seconds without a hook event before a working session reads as stuck.
    static let stuckThreshold = 60

    /// Compact token count ("820", "12k", "1.2M") for the hover detail.
    static func shortTokens(_ count: Int) -> String {
        switch count {
        case ..<1_000:      return "\(count)"
        case ..<1_000_000:  return "\(count / 1_000)k"
        default:            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

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
        // A finished session reads as a calm, definitive green check with "Done" — closure that
        // doesn't keep a live timer running as it winds down.
        if state == .done {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
        } else {
            HStack(spacing: 5) {
                // A healthily running agent gets the live beacon; a stuck (amber) or waiting one
                // stays a calm static dot so "needs attention" never masquerades as smooth progress.
                if state == .working && !stuck {
                    WorkingDot(color: color, size: 6)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
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

/// A subtle branch tag (a branch glyph + name) riding alongside a row's project, so two agents in
/// different worktrees of the same repo are immediately distinguishable. Stays quiet (tertiary).
struct BranchTag: View {
    let branch: String
    let theme: IslandTheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8.5, weight: .semibold))
            Text(branch)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(theme.tertiaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(theme.controlFill.opacity(0.6)))
        .layoutPriority(0)
    }
}
