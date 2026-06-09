import Foundation

/// Controls the macOS Energy Mode (`pmset powermode`): Automatic / Low Power / High Power.
///
/// Reading the mode needs no privilege (`pmset -g`), but changing it requires root
/// (`pmset -a powermode <N>`). A proper SMAppService/SMJobBless helper isn't possible under
/// ad-hoc signing, so we install a one-time root LaunchDaemon. After the (single) admin prompt,
/// every switch is silent: we write a validated `0/1/2` digit to a watched trigger file and the
/// daemon applies it. The daemon — not this process — runs `pmset`, and it strictly validates the
/// trigger content to a single digit before doing so, so no user-controlled text reaches a shell.
final class PowerModeService {
    enum PowerMode: Int, CaseIterable {
        case automatic = 0
        case lowPower = 1
        case highPower = 2

        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .lowPower:  return "Low Power"
            case .highPower: return "High Power"
            }
        }
    }

    // Fixed, code-controlled paths. None of these ever incorporate user input.
    private let supportDir = "/Library/Application Support/Islet"
    private let triggerPath = "/Library/Application Support/Islet/requested_powermode"
    private let scriptPath = "/Library/Application Support/Islet/apply-powermode.sh"
    private let daemonPlistPath = "/Library/LaunchDaemons/com.islet.powermode.plist"
    private let daemonLabel = "com.islet.powermode"

    // MARK: - Reading (no privilege required)

    /// Reads the active Energy Mode by parsing the `powermode` line of `pmset -g`.
    /// Defaults to `.automatic` if the line is absent or unparseable.
    func currentMode() -> PowerMode {
        guard let output = runReadOnly(launchPath: "/usr/bin/pmset", arguments: ["-g"]) else {
            return .automatic
        }
        return Self.parsePowerMode(from: output)
    }

    /// Parses the trailing integer of the ` powermode            N` line.
    static func parsePowerMode(from pmsetOutput: String) -> PowerMode {
        for line in pmsetOutput.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.first == "powermode", fields.count >= 2 else { continue }
            if let value = Int(fields[1]), let mode = PowerMode(rawValue: value) {
                return mode
            }
        }
        return .automatic
    }

    /// Whether the one-time root LaunchDaemon has been installed.
    func isHelperInstalled() -> Bool {
        FileManager.default.fileExists(atPath: daemonPlistPath)
    }

    // MARK: - Writing (privileged, one-time install then silent)

    /// Applies a new Energy Mode. Installs the helper on first use (admin prompt), then writes the
    /// validated digit to the watched trigger file. The daemon picks it up and runs `pmset`.
    /// - Parameter completion: called on the main queue with the (possibly refreshed) current mode.
    func setMode(_ mode: PowerMode, completion: ((PowerMode) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if !self.isHelperInstalled() {
                let installed = self.installHelper()
                if !installed {
                    // User cancelled the prompt or the install failed; report the unchanged mode.
                    let current = self.currentMode()
                    DispatchQueue.main.async { completion?(current) }
                    return
                }
            }

            // Only ever a single constrained digit ("0", "1", or "2") is written.
            let digit = String(mode.rawValue)
            try? digit.write(toFile: self.triggerPath, atomically: true, encoding: .utf8)

            // Give the daemon a moment to fire on the WatchPath and apply pmset, then re-read.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                let current = self.currentMode()
                DispatchQueue.main.async { completion?(current) }
            }
        }
    }

    /// Performs the ONE-TIME privileged install: writes an installer script to a temp file and runs
    /// it with administrator privileges via NSAppleScript (`do shell script ... with administrator
    /// privileges`). Returns true on success, false if the user cancels or the install errors.
    @discardableResult
    func installHelper() -> Bool {
        let tmpDir = NSTemporaryDirectory()
        let installerPath = (tmpDir as NSString)
            .appendingPathComponent("islet-powermode-install-\(UUID().uuidString).sh")

        let installerScript = makeInstallerScript()
        do {
            try installerScript.write(toFile: installerPath, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(atPath: installerPath) }

        // The only interpolation is `installerPath`, a process-generated temp path (no user input).
        let appleScriptSource =
            "do shell script \"/bin/bash '\(installerPath)'\" with administrator privileges"

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: appleScriptSource) else { return false }
        script.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            // Includes the -128 "User cancelled" case.
            return false
        }
        return isHelperInstalled()
    }

    // MARK: - Installer script

    /// Builds the bash installer run once as root. It creates the support dir, the validating
    /// apply script, the LaunchDaemon plist, and the user-writable trigger file, then bootstraps
    /// the daemon. The apply script strictly validates the trigger content to a single 0/1/2 digit
    /// before invoking `pmset`, so no free-text ever reaches a shell.
    private func makeInstallerScript() -> String {
        return """
        #!/bin/bash
        set -e

        SUPPORT_DIR="/Library/Application Support/Islet"
        APPLY_SCRIPT="$SUPPORT_DIR/apply-powermode.sh"
        TRIGGER="$SUPPORT_DIR/requested_powermode"
        PLIST="/Library/LaunchDaemons/com.islet.powermode.plist"

        /bin/mkdir -p "$SUPPORT_DIR"
        /usr/sbin/chown root:wheel "$SUPPORT_DIR"
        /bin/chmod 755 "$SUPPORT_DIR"

        # Apply script: validates the trigger content to exactly 0/1/2, then runs pmset.
        /bin/cat > "$APPLY_SCRIPT" <<'APPLY_EOF'
        #!/bin/bash
        mode=$(/usr/bin/head -c1 "/Library/Application Support/Islet/requested_powermode" 2>/dev/null | /usr/bin/tr -dc '012')
        case "$mode" in
            0|1|2) /usr/bin/pmset -a powermode "$mode" ;;
            *) exit 0 ;;
        esac
        APPLY_EOF
        /usr/sbin/chown root:wheel "$APPLY_SCRIPT"
        /bin/chmod 755 "$APPLY_SCRIPT"

        # LaunchDaemon: fires the apply script whenever the trigger file changes.
        /bin/cat > "$PLIST" <<'PLIST_EOF'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.islet.powermode</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>/Library/Application Support/Islet/apply-powermode.sh</string>
            </array>
            <key>WatchPaths</key>
            <array>
                <string>/Library/Application Support/Islet/requested_powermode</string>
            </array>
            <key>RunAtLoad</key>
            <false/>
        </dict>
        </plist>
        PLIST_EOF
        /usr/sbin/chown root:wheel "$PLIST"
        /bin/chmod 644 "$PLIST"

        # Trigger file: created empty and made world-writable so the app can update it without root.
        # Safe because the daemon validates the content to a single 0/1/2 digit before use.
        if [ ! -f "$TRIGGER" ]; then
            /usr/bin/touch "$TRIGGER"
        fi
        /usr/sbin/chown root:wheel "$TRIGGER"
        /bin/chmod 666 "$TRIGGER"

        # Bootstrap (modern) with a fallback to legacy load.
        /bin/launchctl bootstrap system "$PLIST" 2>/dev/null || /bin/launchctl load -w "$PLIST" 2>/dev/null || true

        exit 0
        """
    }

    // MARK: - Process helpers

    /// Runs a read-only command and returns its stdout as a string, or nil on failure.
    /// Uses Foundation `Process` directly (no shell), with a fixed executable path and a fixed
    /// argument list — no user-controlled input is ever passed.
    private func runReadOnly(launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
