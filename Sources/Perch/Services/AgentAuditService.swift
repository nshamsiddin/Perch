import Foundation

/// Privacy-safe audit trail of island approval decisions. Each allow/deny/stop appends one JSONL
/// line to `~/.perch/agent-audit.jsonl` — coarse metadata only, never full prompts or commands.
final class AgentAuditService {
    private let logURL: URL
    private let queue = DispatchQueue(label: "com.perch.agentaudit")
    private let maxRecentEntries = 20

    init(logURL: URL = PerchPaths.agentAuditLog) {
        self.logURL = logURL
        PerchPaths.ensurePerchDir()
    }

    enum Decision: String {
        case allow, deny, stop
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let timestamp: Date
        let sessionID: String
        let tool: String
        let target: String?
        let decision: Decision
        let note: String?
        let project: String
        let branch: String?

        var decisionLabel: String { decision.rawValue.capitalized }
    }

    /// Records a decision for the given session. Target and note are clipped to the same limits as
    /// the gate hooks so nothing sensitive slips into the log.
    func record(_ decision: Decision, session: AgentSession, note: String? = nil) {
        var entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "session_id": sanitizedSessionID(session),
            "tool": session.tool.rawValue,
            "decision": decision.rawValue,
            "project": clipProject(session.project),
        ]
        if let target = clipTarget(session.pendingApproval?.target) { entry["target"] = target }
        if let note = clip(note) { entry["note"] = note }
        if let branch = clipBranch(session.branch) { entry["branch"] = branch }

        queue.async { [logURL] in
            PerchPaths.ensurePerchDir()
            guard let data = try? JSONSerialization.data(withJSONObject: entry),
                  let line = String(data: data, encoding: .utf8) else { return }
            let payload = line + "\n"
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(payload.data(using: .utf8) ?? Data())
                try? handle.close()
            } else {
                try? payload.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Returns the most recent audit entries, newest first.
    func recentEntries(limit: Int = 20) -> [Entry] {
        let capped = min(max(limit, 1), maxRecentEntries)
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let formatter = ISO8601DateFormatter()
        var entries: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ts = json["ts"] as? String,
                  let date = formatter.date(from: ts),
                  let sessionID = json["session_id"] as? String,
                  let tool = json["tool"] as? String,
                  let decisionRaw = json["decision"] as? String,
                  let decision = Decision(rawValue: decisionRaw),
                  let project = json["project"] as? String else { continue }

            entries.append(Entry(
                id: "\(ts)-\(sessionID)-\(decisionRaw)",
                timestamp: date,
                sessionID: sessionID,
                tool: tool,
                target: json["target"] as? String,
                decision: decision,
                note: json["note"] as? String,
                project: project,
                branch: json["branch"] as? String
            ))
            if entries.count >= capped { break }
        }
        return entries
    }

    // MARK: - Sanitization (mirrors gate-hook clipping)

    private func sanitizedSessionID(_ session: AgentSession) -> String {
        if let colon = session.id.firstIndex(of: ":") {
            return String(session.id[session.id.index(after: colon)...])
        }
        return session.id
    }

    private func clipTarget(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(280))
    }

    private func clip(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(280))
    }

    private func clipProject(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private func clipBranch(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(80))
    }
}
