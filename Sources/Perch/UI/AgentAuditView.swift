import SwiftUI

/// Simple read-only list of recent island approval decisions, opened from the menu bar.
struct AgentAuditView: View {
    let entries: [AgentAuditService.Entry]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = IslandTheme(scheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent decisions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if entries.isEmpty {
                Text("No decisions yet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            AgentAuditRow(entry: entry, theme: theme)
                            Divider().opacity(0.35)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .frame(width: 360, height: 320)
        .background(theme.panelBackground)
    }
}

private struct AgentAuditRow: View {
    let entry: AgentAuditService.Entry
    let theme: IslandTheme

    private var decisionColor: Color {
        switch entry.decision {
        case .allow: return .green
        case .deny:  return .red
        case .stop:  return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.decisionLabel)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(decisionColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(decisionColor.opacity(0.14)))

                Text(entry.project)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(Self.shortTime(entry.timestamp))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.tertiaryText)
            }

            HStack(spacing: 6) {
                Text(entry.tool)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryText)
                if let target = entry.target, !target.isEmpty {
                    Text("·")
                        .foregroundStyle(theme.tertiaryText)
                    Text(target)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                if let branch = entry.branch, !branch.isEmpty {
                    Text("·")
                        .foregroundStyle(theme.tertiaryText)
                    Text(branch)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
