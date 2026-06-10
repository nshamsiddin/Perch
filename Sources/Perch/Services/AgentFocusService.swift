import AppKit

/// Refocuses the window an agent is running in when its island row (or its notification) is tapped.
///
/// Strategy, from most to least specific, falling back gracefully:
///   • Cursor sessions  → open the workspace folder in Cursor, which raises the existing window for
///     that folder (no AppleScript, no shell — uses `NSWorkspace`).
///   • Terminal sessions → activate the hosting app by bundle id, then best-effort select the exact
///     tab/window via AppleScript (Apple Terminal by tty, iTerm2 by session id).
///   • Anything else     → just activate the hosting app.
///
/// Every value interpolated into AppleScript is re-validated against a strict allowlist here (the
/// hook writers already sanitize them) so the generated script can't be injected into.
final class AgentFocusService {
    /// Bundle ids we can drive with tab-level AppleScript.
    private enum Terminal {
        static let appleTerminal = "com.apple.Terminal"
        static let iterm2 = "com.googlecode.iterm2"
    }

    func focus(_ session: AgentSession) {
        if session.tool == .cursor {
            if focusCursorWorkspace(cwd: session.cwd) { return }
        }
        focusTerminal(session.focus)
    }

    // MARK: - Cursor

    /// Opens the agent's workspace folder with the running Cursor app, which focuses (or reopens)
    /// the matching window. Returns false if Cursor isn't found so the caller can fall back.
    private func focusCursorWorkspace(cwd: String) -> Bool {
        guard !cwd.isEmpty else { return activateRunning(matching: "cursor") }
        let folder = URL(fileURLWithPath: cwd, isDirectory: true)
        guard let cursorURL = cursorAppURL() else {
            return activateRunning(matching: "cursor")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: cursorURL, configuration: config)
        return true
    }

    private func cursorAppURL() -> URL? {
        // Prefer a running instance's bundle id; otherwise look it up by the conventional id / name.
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier ?? "").lowercased().contains("cursor") ||
            ($0.localizedName ?? "").lowercased() == "cursor"
        }), let url = running.bundleURL {
            return url
        }
        let ws = NSWorkspace.shared
        let candidates = ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor", "com.cursor.cursor"]
        for id in candidates {
            if let url = ws.urlForApplication(withBundleIdentifier: id) { return url }
        }
        let appPath = "/Applications/Cursor.app"
        return FileManager.default.fileExists(atPath: appPath) ? URL(fileURLWithPath: appPath) : nil
    }

    // MARK: - Terminals

    private func focusTerminal(_ hint: FocusHint?) {
        guard let hint else { return }
        // Bring the hosting app forward first; reliable and permission-free.
        if let bundleID = hint.bundleID, !bundleID.isEmpty {
            _ = activate(bundleID: bundleID)
        } else if let app = hint.app, !app.isEmpty {
            _ = activateRunning(matching: termProgramKeyword(app))
        }

        let bundle = hint.bundleID ?? ""
        if bundle == Terminal.appleTerminal || hint.app == "Apple_Terminal" {
            selectAppleTerminalTab(tty: hint.tty)
        } else if bundle == Terminal.iterm2 || hint.app == "iTerm.app" {
            selectITermSession(sessionID: hint.sessionID)
        }
    }

    /// Maps a TERM_PROGRAM value to a substring we can match against a running app's name.
    private func termProgramKeyword(_ termProgram: String) -> String {
        switch termProgram {
        case "Apple_Terminal": return "terminal"
        case "iTerm.app":      return "iterm"
        default:               return termProgram.lowercased()
        }
    }

    // MARK: - App activation

    @discardableResult
    private func activate(bundleID: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let app = apps.first else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    @discardableResult
    private func activateRunning(matching keyword: String) -> Bool {
        let key = keyword.lowercased()
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier ?? "").lowercased().contains(key) ||
            ($0.localizedName ?? "").lowercased().contains(key)
        }) else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    // MARK: - AppleScript tab selection

    private func selectAppleTerminalTab(tty: String?) {
        guard let tty = validatedTTY(tty) else { return }
        // Find the window whose selected tab's tty matches, raise it, and bring Terminal forward.
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    private func selectITermSession(sessionID: String?) {
        guard let sid = validatedSessionID(sessionID) else { return }
        // ITERM_SESSION_ID looks like "w0t1p0:UUID"; iTerm's `id` is the trailing UUID.
        let uuid = sid.contains(":") ? String(sid.split(separator: ":").last ?? "") : sid
        guard let id = validatedSessionID(uuid) else { return }
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "\(id)" then
                            select w
                            select t
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    /// Runs AppleScript off the main thread (it may block on the Automation permission prompt).
    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            // Errors (e.g. permission denied, tab gone) are non-fatal: the app was already raised.
        }
    }

    // MARK: - Input validation (defense-in-depth before AppleScript interpolation)

    func validatedTTY(_ value: String?) -> String? {
        guard let value, value.hasPrefix("/dev/"),
              value.range(of: "^/dev/[A-Za-z0-9./-]+$", options: .regularExpression) != nil
        else { return nil }
        return value
    }

    func validatedSessionID(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value.range(of: "^[A-Za-z0-9:_-]+$", options: .regularExpression) != nil
        else { return nil }
        return value
    }
}
