import Foundation
import Darwin

/// The island's *return channel* to running agents. Where `AgentStatusService` reads agent state,
/// this writes back: a small per-session command file the (blocking) gate hooks poll to learn the
/// user's decision (allow / deny), an optional steering note, and a stop request. It also publishes
/// the gating config the Claude gate hook reads to decide whether to block at all, and can SIGINT a
/// recorded agent process for an immediate stop.
///
/// Mirrors the hook writers' conventions: files are written atomically (temp + rename) so a hook
/// never reads a half-written command, and every value is held to a strict allowlist before it is
/// used in a filename (defense-in-depth — the ids were already sanitized at the source).
final class AgentCommandService {
    private let claudeCommandsDir: URL
    private let cursorCommandsDir: URL

    /// Default set of Claude tools routed through the island when Control is on. Kept to the tools
    /// that actually have side effects, so trivial reads/searches don't pause on every call.
    static let defaultGatedTools = ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "WebFetch"]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeCommandsDir = home.appendingPathComponent(".claude/agent-commands", isDirectory: true)
        self.cursorCommandsDir = home.appendingPathComponent(".cursor/agent-commands", isDirectory: true)
        ensureDirectories()
    }

    private func ensureDirectories() {
        for dir in [claudeCommandsDir, cursorCommandsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Decisions

    /// Approve the session's pending tool call, optionally injecting a short steering note that the
    /// agent (Claude) sees as additional context before the call runs.
    func approve(_ session: AgentSession, note: String? = nil) {
        guard let request = session.pendingApproval else { return }
        var command: [String: Any] = [
            "request_id": request.requestID,
            "decision": "allow",
            "ts": Date().timeIntervalSince1970,
        ]
        if let note = clip(note) { command["note"] = note }
        write(command: command, for: session)
    }

    /// Deny the session's pending tool call. `reason` is fed back to the agent so it can adapt.
    func deny(_ session: AgentSession, reason: String? = nil) {
        guard let request = session.pendingApproval else { return }
        write(command: [
            "request_id": request.requestID,
            "decision": "deny",
            "reason": clip(reason) ?? "Denied from Perch",
            "ts": Date().timeIntervalSince1970,
        ], for: session)
    }

    // MARK: - Stop

    /// Best-effort stop: SIGINT the recorded agent process (like Ctrl-C) and leave a `stop` command
    /// so the next gated tool call is denied too. No hook API exists to truly halt a run, so this is
    /// a best-effort interrupt; the deny-next backstop catches agents we can't signal (e.g. Cursor).
    func stop(_ session: AgentSession) {
        if session.tool == .claudeCode, let pid = session.pid, pid > 1 {
            // os.kill with an integer pid only — no shell, no untrusted input.
            _ = Darwin.kill(pid_t(pid), SIGINT)
        }
        write(command: [
            "request_id": session.pendingApproval?.requestID ?? "stop",
            "decision": "deny",
            "reason": "Stopped from Perch",
            "stop": true,
            "ts": Date().timeIntervalSince1970,
        ], for: session)
    }

    // MARK: - Gating config

    /// Publishes whether the Claude gate hook should block tool calls on the island, and which
    /// tools. Written to both command dirs so each tool's gate reads a local copy.
    func setGating(enabled: Bool, tools: [String] = AgentCommandService.defaultGatedTools) {
        let config: [String: Any] = ["gating": enabled, "tools": tools]
        for dir in [claudeCommandsDir, cursorCommandsDir] {
            atomicWrite(config, to: dir.appendingPathComponent("_config.json"))
        }
    }

    // MARK: - File IO

    /// Writes the decision file for a session into the tool's command directory, named by the raw
    /// (sanitized) session id so the matching gate hook finds it.
    private func write(command: [String: Any], for session: AgentSession) {
        guard let dir = commandsDir(for: session.tool),
              let name = commandFileName(for: session) else { return }
        // Strip nil values (e.g. an omitted note) so we never serialize NSNull.
        let cleaned = command.filter { !($0.value is NSNull) }
        atomicWrite(cleaned, to: dir.appendingPathComponent("\(name).json"))
    }

    private func commandsDir(for tool: AgentTool) -> URL? {
        switch tool {
        case .claudeCode: return claudeCommandsDir
        case .cursor:     return cursorCommandsDir
        }
    }

    /// The raw session id (everything after the "tool:" prefix in `AgentSession.id`), re-sanitized
    /// to the filename allowlist as defense-in-depth before it becomes a path component.
    private func commandFileName(for session: AgentSession) -> String? {
        let raw: String
        if let colon = session.id.firstIndex(of: ":") {
            raw = String(session.id[session.id.index(after: colon)...])
        } else {
            raw = session.id
        }
        return Self.sanitizedFileName(raw)
    }

    /// Maps a raw session id to a safe filename: every character outside the allowlist becomes `_`,
    /// and leading/trailing `.`/`_` are trimmed. Returns nil if nothing usable remains. Pure and
    /// security-sensitive (this becomes a path component), so it's unit-tested directly.
    static func sanitizedFileName(_ raw: String) -> String? {
        let sanitized = raw.unicodeScalars.map { scalar -> Character in
            filenameAllowed.contains(scalar) ? Character(scalar) : "_"
        }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return result.isEmpty ? nil : result
    }

    private static let filenameAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "._-")
        return set
    }()

    /// Atomic JSON write so a polling hook never sees a partial file. `Data.write(.atomic)` writes
    /// to a sibling temp file and renames into place, which is exactly what the hooks expect.
    private func atomicWrite(_ object: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func clip(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(280))
    }
}
