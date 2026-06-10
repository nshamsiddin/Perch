import AppKit
import Combine

/// Visual mode of the island.
enum IslandMode: Equatable {
    case collapsed
    case expanded
}

/// Now-playing snapshot surfaced by `MediaService`.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var source: String // "Music" or "Spotify"

    static let empty = NowPlaying(title: "", artist: "", album: "", isPlaying: false, source: "")

    var hasContent: Bool { !title.isEmpty }
}

/// Battery / power snapshot surfaced by `BatteryService`.
struct BatteryStatus: Equatable {
    var percentage: Int          // 0...100, -1 when unknown
    var isCharging: Bool
    var isPluggedIn: Bool
    var hasBattery: Bool

    static let unknown = BatteryStatus(percentage: -1, isCharging: false, isPluggedIn: false, hasBattery: false)
}

/// A transient output-volume HUD shown flanking the notch when volume/mute changes.
struct VolumeHUD: Equatable {
    var level: Double   // 0.0...1.0 output scalar
    var muted: Bool
}

/// Which AI coding tool a running agent belongs to. Drives the glyph/label in the island.
enum AgentTool: String, Equatable {
    case claudeCode
    case cursor

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .cursor:     return "Cursor"
        }
    }

    /// SF Symbol used to represent the tool (collapsed ear + expanded list).
    var symbol: String {
        switch self {
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        case .cursor:     return "cursorarrow"
        }
    }
}

/// Lifecycle state of a single agent session, derived from hook events + recency.
enum AgentRunState: Equatable {
    case working   // actively generating / running tools
    case waiting   // paused, needs user input (permission / notification)
    case done      // finished its turn
}

/// Hints used to refocus the exact window/tab an agent is running in. All fields are best-effort
/// and sanitized at the source (hook writers) — `app` is the terminal/editor program, `sessionID`
/// is a terminal session identifier (e.g. ITERM_SESSION_ID), `tty` the controlling tty path.
struct FocusHint: Equatable {
    var app: String?        // TERM_PROGRAM (e.g. "iTerm.app", "Apple_Terminal")
    var bundleID: String?   // hosting app's bundle id (__CFBundleIdentifier), most reliable to focus
    var sessionID: String?  // terminal session id (ITERM_SESSION_ID / TERM_SESSION_ID)
    var tty: String?        // controlling tty path (for Apple Terminal tab matching)

    var isEmpty: Bool {
        [app, bundleID, sessionID, tty].allSatisfy { ($0 ?? "").isEmpty }
    }
}

/// A pending tool-permission request a gated agent is blocking on, surfaced when the user has
/// enabled Control. The island answers it by writing a decision (allow/deny) keyed by `requestID`
/// back to the agent's command file; `requestID` guards against acting on a stale prompt.
struct ApprovalRequest: Equatable {
    let requestID: String   // matches the gate hook's pending request; echoed back in the decision
    var toolName: String?   // e.g. "Bash", "Write" — the tool about to run
    var target: String?     // coarse target (file basename / command program token), never full args
    var summary: String     // short human line for the row, e.g. "Run rm" / "Edit Foo.swift"
}

/// A single tracked agent session (one Claude Code session or one Cursor conversation).
/// The service publishes only the *active* sessions; the UI renders them directly.
struct AgentSession: Identifiable, Equatable {
    let id: String          // "claudeCode:<sessionID>" / "cursor:<conversationID>"
    var tool: AgentTool
    var project: String     // basename of the working directory, for display
    var cwd: String         // raw working directory, used to refocus Cursor's window
    var state: AgentRunState
    var updatedAt: Date
    var activity: String?   // short human phrase: what the agent is doing right now
    var focus: FocusHint?   // hints to refocus the owning terminal tab / editor window
    /// Git branch the agent's working directory is on, when resolvable (great for telling apart
    /// several agents running in worktrees of the same repo). Nil when not in a git repo.
    var branch: String?
    /// Model the agent is running on (e.g. "Sonnet"), surfaced as a secondary hover detail. Nil
    /// when the tool doesn't report one.
    var model: String?
    /// Best-effort token count for the latest turn, paired with `model` on hover. Nil when unknown.
    var tokens: Int?
    /// Set when the agent is blocking on a tool-permission decision (Control mode). Drives the
    /// inline Approve/Deny buttons; nil for ordinary working/waiting/done sessions.
    var pendingApproval: ApprovalRequest?
    /// Best-effort process id of the agent (recorded by the hook), used by Stop to send SIGINT.
    var pid: Int?

    var isWorking: Bool { state == .working }
    var isWaiting: Bool { state == .waiting }
    var isDone: Bool { state == .done }
    /// True while this session is blocking on an island approval decision.
    var isAwaitingApproval: Bool { pendingApproval != nil }
}

/// A transient live-activity peek.
struct Activity: Identifiable, Equatable {
    let id: UUID
    var symbol: String   // SF Symbol name
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), symbol: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.symbol = symbol
        self.text = text
        self.createdAt = createdAt
    }
}

/// Shared, observable application state. The single source of truth bound to the SwiftUI island.
final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .collapsed
    @Published var geometry: NotchGeometry = .fallback
    @Published var isHiddenForFullScreen: Bool = false

    // MARK: - Feature toggles (user settings, persisted in UserDefaults; all default on)
    // These are the single source of truth for which features are active. Views observe them for
    // visibility, the window controller for sizing, and `AppServices` to start/stop the backing
    // services so a disabled feature stops doing work (timers, AppleScript prompts, file watching).

    @Published var mediaEnabled: Bool = IslandState.loadFlag(SettingsKey.media) {
        didSet { IslandState.saveFlag(SettingsKey.media, mediaEnabled) }
    }
    @Published var batteryEnabled: Bool = IslandState.loadFlag(SettingsKey.battery) {
        didSet { IslandState.saveFlag(SettingsKey.battery, batteryEnabled) }
    }
    @Published var agentsEnabled: Bool = IslandState.loadFlag(SettingsKey.agents) {
        didSet { IslandState.saveFlag(SettingsKey.agents, agentsEnabled) }
    }
    /// Whether a Notification Center alert + sound fires when an agent starts waiting for input.
    @Published var notifyOnWaiting: Bool = IslandState.loadFlag(SettingsKey.notify) {
        didSet { IslandState.saveFlag(SettingsKey.notify, notifyOnWaiting) }
    }
    /// Whether the island can *act* on agents (approve/deny permission prompts, stop a run). Unlike
    /// the other flags this defaults OFF: enabling it makes Claude's gated tool calls block on the
    /// island, a behavior change the user opts into explicitly.
    @Published var agentsControlEnabled: Bool = IslandState.loadFlag(SettingsKey.control, default: false) {
        didSet { IslandState.saveFlag(SettingsKey.control, agentsControlEnabled) }
    }
    /// When set and in the future, gate hooks skip blocking until this instant (snooze). Cleared on
    /// resume or when the deadline passes. Persisted as an ISO-8601 string.
    @Published var gatingPausedUntil: Date? = IslandState.loadPausedUntil() {
        didSet { IslandState.savePausedUntil(gatingPausedUntil) }
    }

    private enum SettingsKey {
        static let media = "feature.media.enabled"
        static let battery = "feature.battery.enabled"
        static let agents = "feature.agents.enabled"
        static let notify = "feature.agents.notify"
        static let control = "feature.agents.control"
        static let gatingPausedUntil = "feature.agents.gatingPausedUntil"
    }

    /// Reads a persisted feature flag, defaulting to `defaultValue` when never set.
    private static func loadFlag(_ key: String, default defaultValue: Bool = true) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func saveFlag(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static let pausedUntilFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func loadPausedUntil() -> Date? {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.gatingPausedUntil) else { return nil }
        return pausedUntilFormatter.date(from: raw)
    }

    private static func savePausedUntil(_ date: Date?) {
        let defaults = UserDefaults.standard
        if let date {
            defaults.set(pausedUntilFormatter.string(from: date), forKey: SettingsKey.gatingPausedUntil)
        } else {
            defaults.removeObject(forKey: SettingsKey.gatingPausedUntil)
        }
    }

    @Published var nowPlaying: NowPlaying = .empty
    /// Album artwork for the current track. Kept out of `NowPlaying` so the struct can stay
    /// `Equatable` (NSImage isn't value-comparable) and so artwork can update independently.
    @Published var artwork: NSImage?
    @Published var battery: BatteryStatus = .unknown

    /// Most-recent live activity, shown as a transient peek next to the notch.
    @Published var currentActivity: Activity?

    /// Transient output-volume HUD; non-nil while the speaker/level HUD is visible.
    @Published var volumeHUD: VolumeHUD?

    /// Currently *active* AI agent sessions (Claude Code / Cursor). Already TTL-filtered by
    /// `AgentStatusService`, so any session present here drives the live indicator.
    @Published var agentSessions: [AgentSession] = []

    /// Bumped each time an agent newly transitions to *waiting*; the island observes it to play a
    /// brief amber attention flash. The id changes so back-to-back events each retrigger.
    @Published var agentAttention: UUID?

    // MARK: - Feature-gated views of the raw state
    // The UI and layout should read these (not the raw fields) so a disabled feature disappears
    // everywhere consistently.

    /// Agent sessions to actually surface — empty when the AI feature is disabled.
    var visibleAgentSessions: [AgentSession] { agentsEnabled ? agentSessions : [] }

    /// True while now-playing content should be shown (media feature on + something playing).
    var nowPlayingActive: Bool { mediaEnabled && nowPlaying.hasContent }

    /// True while the battery chip should be shown (battery feature on + a battery present).
    var batteryActive: Bool { batteryEnabled && battery.hasBattery }

    /// True when the expanded panel's top row has anything to show.
    var showsContentRow: Bool { mediaEnabled || batteryEnabled }

    /// True while at least one agent is actively working or waiting for input.
    var hasActiveAgents: Bool { !visibleAgentSessions.isEmpty }

    var agentWorkingCount: Int { agentSessions.lazy.filter { $0.isWorking }.count }
    var agentWaitingCount: Int { agentSessions.lazy.filter { $0.isWaiting }.count }

    /// True while the island may act on agents: the AI feature and Control are both on.
    var agentsControlActive: Bool { agentsEnabled && agentsControlEnabled }

    /// True while gating is snoozed — hooks fail open until the pause deadline passes.
    var isGatingPaused: Bool {
        guard let until = gatingPausedUntil else { return false }
        return until > Date()
    }

    /// Visible sessions currently blocking on an island approval decision (drives taller rows).
    var agentApprovalCount: Int { visibleAgentSessions.lazy.filter { $0.isAwaitingApproval }.count }

    /// Distinct tools that currently have an active session, in a stable display order.
    var activeAgentTools: [AgentTool] {
        [.claudeCode, .cursor].filter { tool in agentSessions.contains { $0.tool == tool } }
    }

    func setMode(_ newMode: IslandMode) {
        guard mode != newMode else { return }
        mode = newMode
    }
}
