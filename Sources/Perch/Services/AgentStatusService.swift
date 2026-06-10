import Foundation
import CoreServices
import SwiftUI

/// Tracks running AI coding agents (Claude Code & Cursor) and surfaces the *active* sessions in
/// `IslandState`. Status is hook-driven: each tool writes a small per-session JSON file when its
/// agent starts / runs tools / waits / finishes, and this service watches those directories.
///
/// Sources:
///   • Claude Code  → `~/.claude/agent-tui-state/<session>.json` (existing PreToolUse/PostToolUse/
///     Stop hooks, extended with UserPromptSubmit/Notification/SubagentStop writers).
///   • Cursor       → `~/.cursor/agent-status/<conversation>.json` (our beforeSubmitPrompt/stop hooks).
///
/// Watching is event-driven via FSEvents (no polling at rest). A short safety tick runs *only*
/// while at least one session is active, so a session that dies mid-turn without emitting a
/// terminal event still expires by TTL.
final class AgentStatusService {
    private let state: IslandState
    private let activity: ActivityCenter

    /// Invoked on the main thread when a session newly transitions to `.waiting` (it wasn't
    /// waiting in the previous publish). Used to fire the Notification Center alert.
    var onNewWaiting: ((AgentSession) -> Void)?

    /// Run state of each session as of the last publish, to detect waiting-transitions.
    private var lastStates: [String: AgentRunState] = [:]

    private let claudeDir: URL
    private let cursorDir: URL
    private let claudeCommandsDir: URL
    private let cursorCommandsDir: URL

    private let queue = DispatchQueue(label: "com.perch.agentstatus")
    private var stream: FSEventStreamRef?
    private var tickTimer: Timer?

    // MARK: Tunables
    /// A `.working` session is considered active only while updated within this window. Guards
    /// against turns that end without a terminal event (e.g. the process was killed). Kept generous
    /// so a long-running single tool call (no interim hook event) stays visible — and reads as
    /// "stuck" (amber elapsed time) in the UI — instead of silently vanishing.
    private let workingTTL: TimeInterval = 180
    /// A `.waiting` session persists longer: it intentionally idles until the user responds.
    private let waitingTTL: TimeInterval = 1800
    /// A `.done` session lingers just long enough to register as "finished" in the UI (a green
    /// check), giving closure, then drops so the panel collapses. Kept short so a just-finished
    /// agent flashes done rather than vanishing silently.
    private let doneTTL: TimeInterval = 6
    /// Files older than this are skipped without parsing (the Claude dir holds many stale files).
    private var scanTTL: TimeInterval { max(workingTTL, waitingTTL) }
    private let tickInterval: TimeInterval = 2.0
    /// FSEvents coalescing latency.
    private let streamLatency: CFTimeInterval = 0.3

    init(state: IslandState, activity: ActivityCenter) {
        self.state = state
        self.activity = activity
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeDir = home.appendingPathComponent(".claude/agent-tui-state", isDirectory: true)
        self.cursorDir = home.appendingPathComponent(".cursor/agent-status", isDirectory: true)
        self.claudeCommandsDir = home.appendingPathComponent(".claude/agent-commands", isDirectory: true)
        self.cursorCommandsDir = home.appendingPathComponent(".cursor/agent-commands", isDirectory: true)
    }

    // MARK: - Lifecycle

    func start() {
        ensureDirectories()
        startStream()
        // Initial scan so an already-running agent shows up immediately at launch.
        scanAndPublish()
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Both directories must exist for FSEvents to deliver events reliably; creating them is
    /// harmless (the hooks write here too).
    private func ensureDirectories() {
        // Status dirs are watched; command dirs are where the island writes decisions the gate
        // hooks poll — create both so the back-channel works the first time Control is enabled.
        for dir in [claudeDir, cursorDir, claudeCommandsDir, cursorCommandsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - FSEvents

    private func startStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // C callback: recover `self` from the context's `info` pointer and re-scan.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let service = Unmanaged<AgentStatusService>.fromOpaque(info).takeUnretainedValue()
            service.scanAndPublish()
        }

        let paths = [claudeDir.path, cursorDir.path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), streamLatency, flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    // MARK: - Scan & publish

    /// Always hops onto the private queue for file IO, then publishes on the main thread.
    /// Safe to call from the FSEvents queue (re-entrant on a serial queue) or the main-thread tick.
    private func scanAndPublish() {
        queue.async { [weak self] in
            guard let self else { return }
            let sessions = self.scan()
            DispatchQueue.main.async { self.publish(sessions) }
        }
    }

    private func scan() -> [AgentSession] {
        let now = Date()
        var sessions: [AgentSession] = []
        sessions += scanDirectory(claudeDir, tool: .claudeCode, now: now)
        sessions += scanDirectory(cursorDir, tool: .cursor, now: now)
        // Stable order: active (working/waiting) before just-finished, working before waiting,
        // Claude before Cursor, then by id.
        sessions.sort { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            if lhs.isWorking != rhs.isWorking { return lhs.isWorking }
            if lhs.tool != rhs.tool { return lhs.tool == .claudeCode }
            return lhs.id < rhs.id
        }
        return sessions
    }

    private func scanDirectory(_ dir: URL, tool: AgentTool, now: Date) -> [AgentSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [AgentSession] = []
        for url in entries where url.pathExtension == "json" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = values.contentModificationDate else { continue }
            let age = now.timeIntervalSince(mtime)
            // Cheap pre-filter: skip ancient files without parsing them.
            if age > scanTTL { continue }

            guard let data = try? Data(contentsOf: url),
                  let session = parse(
                    data: data,
                    tool: tool,
                    mtime: mtime,
                    fallbackID: url.deletingPathExtension().lastPathComponent
                  )
            else { continue }

            // Keep only sessions that are currently active under their TTL. A just-finished session
            // lingers briefly (doneTTL) so the UI can show a "finished" beat before it drops.
            switch session.state {
            case .working where age <= workingTTL: sessions.append(session)
            case .waiting where age <= waitingTTL: sessions.append(session)
            case .done where age <= doneTTL: sessions.append(session)
            default: break // stale -> not active
            }
        }
        return sessions
    }

    private func parse(data: Data, tool: AgentTool, mtime: Date, fallbackID: String) -> AgentSession? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var runState: AgentRunState
        let cwd: String
        let sessionID: String

        switch tool {
        case .claudeCode:
            runState = Self.claudeState(for: obj["hook_event_name"] as? String ?? "")
            cwd = obj["cwd"] as? String ?? ""
            sessionID = obj["session_id"] as? String ?? fallbackID
        case .cursor:
            runState = Self.cursorState(for: obj["status"] as? String ?? "")
            cwd = obj["cwd"] as? String ?? Self.firstWorkspaceRoot(obj)
            sessionID = obj["conversation_id"] as? String ?? fallbackID
        }

        let project = cwd.isEmpty ? tool.label : (cwd as NSString).lastPathComponent
        let activity = (obj["activity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let focus = FocusHint(
            app: Self.nonEmpty(obj["term_program"] as? String),
            bundleID: Self.nonEmpty(obj["app_bundle"] as? String),
            sessionID: Self.nonEmpty(obj["term_session"] as? String),
            tty: Self.nonEmpty(obj["tty"] as? String)
        )
        let pendingApproval = Self.pendingApproval(obj, activity: activity)
        // An agent blocking on an island decision is, by definition, waiting on the user — surface
        // it as waiting (and let it persist on the longer waiting TTL) no matter the raw hook event.
        if pendingApproval != nil { runState = .waiting }
        return AgentSession(
            id: "\(tool.rawValue):\(sessionID)",
            tool: tool,
            project: project,
            cwd: cwd,
            state: runState,
            updatedAt: mtime,
            activity: activity,
            focus: focus.isEmpty ? nil : focus,
            branch: Self.nonEmpty(obj["git_branch"] as? String),
            model: Self.nonEmpty(obj["model"] as? String),
            tokens: Self.tokens(obj),
            pendingApproval: pendingApproval,
            pid: Self.pid(obj)
        )
    }

    /// Builds a pending-approval descriptor when a gate hook is blocking on the island. The hook
    /// sets `pending` + a `request_id` while it waits; absent either, the session isn't awaiting us.
    private static func pendingApproval(_ obj: [String: Any], activity: String?) -> ApprovalRequest? {
        guard (obj["pending"] as? Bool) == true,
              let requestID = nonEmpty(obj["request_id"] as? String) else { return nil }
        let toolName = nonEmpty(obj["tool_name"] as? String)
        let target = nonEmpty(obj["target"] as? String)
        return ApprovalRequest(
            requestID: requestID,
            toolName: toolName,
            target: target,
            summary: activity ?? [toolName, target].compactMap { $0 }.joined(separator: " ")
        )
    }

    /// Reads the agent's process id if the hook recorded one (used by Stop). Accepts a JSON number
    /// or a numeric string, and rejects anything non-positive.
    static func pid(_ obj: [String: Any]) -> Int? {
        let value: Int?
        if let n = obj["pid"] as? Int { value = n }
        else if let n = obj["pid"] as? Double { value = Int(n) }
        else if let s = obj["pid"] as? String { value = Int(s) }
        else { value = nil }
        guard let pid = value, pid > 1 else { return nil }
        return pid
    }

    /// Reads the latest-turn token count if the hook recorded one. Accepts a JSON number or numeric
    /// string; rejects non-positive values.
    static func tokens(_ obj: [String: Any]) -> Int? {
        let value: Int?
        if let n = obj["tokens"] as? Int { value = n }
        else if let n = obj["tokens"] as? Double { value = Int(n) }
        else if let s = obj["tokens"] as? String { value = Int(s) }
        else { value = nil }
        guard let tokens = value, tokens > 0 else { return nil }
        return tokens
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func publish(_ sessions: [AgentSession]) {
        // Detect sessions that just entered the waiting state (weren't waiting last time) so we can
        // flash the island + notify exactly once per transition, not on every safety-tick re-scan.
        let newlyWaiting = sessions.filter { $0.isWaiting && lastStates[$0.id] != .waiting }
        lastStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.state) })

        if state.agentSessions != sessions {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                state.agentSessions = sessions
            }
        }

        if !newlyWaiting.isEmpty {
            // A fresh id retriggers the amber attention flash even for back-to-back events.
            state.agentAttention = UUID()
            for session in newlyWaiting { onNewWaiting?(session) }
        }

        updateTick(active: !sessions.isEmpty)
    }

    /// Runs a light re-scan tick only while sessions are active, so stale `.working` sessions
    /// expire by TTL even though no FSEvent fires for them. Idle ⇒ no timer (no polling at rest).
    private func updateTick(active: Bool) {
        if active {
            guard tickTimer == nil else { return }
            let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
                self?.scanAndPublish()
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    // MARK: - State mapping

    static func claudeState(for event: String) -> AgentRunState {
        switch event {
        case "Stop":         return .done
        case "Notification": return .waiting
        // UserPromptSubmit / PreToolUse / PostToolUse / SubagentStop / others ⇒ still working.
        default:             return .working
        }
    }

    static func cursorState(for status: String) -> AgentRunState {
        switch status {
        case "done", "stop": return .done
        default:             return .working
        }
    }

    private static func firstWorkspaceRoot(_ obj: [String: Any]) -> String {
        (obj["workspace_roots"] as? [String])?.first ?? ""
    }
}
