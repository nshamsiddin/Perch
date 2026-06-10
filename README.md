# Perch

A Dynamic Island for the macOS notch. Perch is a lightweight, native AppKit background app
that draws an interactive island around the notch (or a centered pill on non-notch Macs).
Hover to expand it into a panel with now-playing controls and battery/system status.
Transient "live activity" peeks slide out around the notch when things happen — and a live
indicator keeps watch over your AI coding agents.

Built with Swift Package Manager — no Xcode project required.

## Features

- **Hover to expand** — a borderless, transparent window pinned over the notch expands into a
  panel on hover. Uses an `NSTrackingArea(.activeAlways)`, so **no Accessibility permission** is
  needed and there's no polling.
- **Now Playing** — title/artist + play-pause / next / previous for **Music** and **Spotify**,
  driven by each app's distributed notifications for instant updates (with a slow timer fallback),
  plus album artwork.
- **Volume HUD** — a transient output-volume / mute peek flanks the notch on volume changes,
  via CoreAudio property listeners (no permissions). Best-effort suppression of the native bezel
  so only Perch's HUD shows.
- **Battery / power** — charge % and charging state via IOKit (event-driven).
- **Energy Mode** — switch macOS Energy Mode (Automatic / Low Power / High Power) from the menu.
  See *Energy Mode & permissions* below — this is the one feature that needs a one-time admin
  prompt, and it can be removed cleanly.
- **AI agent status** — a live indicator flanks the notch while **Claude Code** and/or **Cursor**
  agents are actively working (tool glyphs + a "thinking" pulse + session count). The pulse turns
  amber when an agent is waiting for input. Hover to see a clean, label-free agent overview: a slim
  working / waiting summary above per-session rows (keyed by project, with a live "what it's doing"
  line and elapsed time), sessions awaiting input floated to the top. Detection is hook-driven —
  see *AI agent tracking* below. The overview doubles as a control surface:
  - **Click a row to jump to that agent** — Perch brings the owning window to the front: Cursor's
    workspace window, or the exact terminal tab (Apple Terminal by tty, iTerm2 by session id),
    falling back to simply activating the app.
  - **Waiting alerts** — when an agent newly needs input, the island flashes amber and (optionally)
    a Notification Center banner + sound fires. Tap the notification to jump straight to the agent.
    Toggle this under *AI Agents → Notify on waiting* in the menu-bar menu.
  - **Control (approve / deny / stop)** — opt in and Perch becomes a control surface for gated
    agent tool calls: approve or deny a pending call (with an optional steering note), or stop a
    run. Off by default; see *Agent Control* below.
  - **Stuck detection** — a working session that goes quiet too long shows its elapsed time in
    amber, so a wedged or long-running agent stands out at a glance.
- **Live activity peeks** — brief notch-flanking peeks for track changes and power events.
- **Feature toggles** — Media, Battery, and AI Agents each have a menu-bar toggle. Turning a
  feature off stops its backing service entirely (no timers, AppleScript prompts, or file watching)
  and collapses it from the island immediately. Settings persist across launches.
- **Automatic light / dark** — the expanded panel follows the system appearance and switches
  live. The collapsed pill and peeks stay dark on purpose so they blend with the physical notch.
- **Full-screen aware** — hides while another app is full-screen (the system overlays the notch).

## Requirements

- macOS 13+ (Apple Silicon or notch Mac recommended; works with a pill on non-notch Macs)
- Swift toolchain (Command Line Tools are enough to **build & run**; running the **tests** needs
  full Xcode, since `XCTest` ships with Xcode — see *Tests* below)

## Build & run

```bash
chmod +x bundle.sh
./bundle.sh
open Perch.app
```

`bundle.sh` builds a release binary, assembles `Perch.app` (with `LSUIElement` so there's no
Dock icon), and **ad-hoc code-signs** it with a stable bundle identifier. Quit anytime from the
menu-bar icon.

## Permissions

- **Automation (Apple Events)** — the first time Perch reads or controls Music/Spotify, macOS
  prompts to allow automating that app. Approve it in
  *System Settings → Privacy & Security → Automation*. Until then, media info/controls stay idle.
- **No Accessibility permission** is required (hover uses a tracking area, not a global monitor).
- **Notifications** — the first waiting alert asks for Notification permission.
- See *Energy Mode & permissions* for the one feature that needs an admin prompt.

### A note on rebuilds and permissions

macOS ties Automation grants to the app's bundle id + code signature. `bundle.sh` re-signs with a
**stable** identity on every build so grants survive rebuilds. If a grant ever gets dropped after a
rebuild, just re-approve it in Automation settings.

## Energy Mode & permissions

Reading the current Energy Mode needs no privilege (`pmset -g`). Changing it requires root
(`pmset -a powermode <N>`), which a sandbox-free, ad-hoc-signed app can't do directly. So the first
time you pick a non-Automatic mode, Perch shows a **one-time administrator prompt** and installs a
small root **LaunchDaemon**:

- `/Library/LaunchDaemons/com.perch.powermode.plist` — watches a trigger file and runs the apply
  script.
- `/Library/Application Support/Perch/apply-powermode.sh` — validates the trigger content to a
  single `0`/`1`/`2` digit and then runs `pmset`. No free-text ever reaches a shell.
- `/Library/Application Support/Perch/requested_powermode` — the trigger file Perch writes the
  validated digit into. After the one install, every switch is silent.

**Removing it.** Use the menu-bar icon → *Energy Mode → Remove Perch helper* (one admin prompt),
or run the standalone uninstaller:

```bash
sudo scripts/uninstall-powermode.sh
```

Both boot out and delete the LaunchDaemon and remove the support directory. If you never use
Energy Mode, nothing is ever installed.

## AI agent tracking (Claude Code + Cursor)

The agent indicator is driven by lightweight **hooks** that each tool runs on its agent lifecycle
events. The hooks write a small per-session JSON status file; Perch watches those directories with
FSEvents (event-driven, no polling at rest) and shows the *active* sessions.

- **Claude Code** → `~/.claude/agent-tui-state/<session>.json`. The `Stop` event marks a session
  done, `Notification` marks it waiting for input, and tool/prompt events mark it working. The
  writer also records a short, privacy-safe activity phrase (a tool name plus a file basename or a
  command's program token — never full prompts or arguments) and best-effort focus hints (the
  hosting app's bundle id, terminal session id, and tty) used for click-to-focus.
- **Cursor** → `~/.cursor/agent-status/<conversation>.json`, written on `beforeSubmitPrompt`
  (working), `afterFileEdit` / `beforeShellExecution` (working + activity), and `stop` (done).

The first time you click a row that targets **Apple Terminal** or **iTerm2**, macOS prompts to
allow Perch to control that app (Automation). Approve it in *System Settings → Privacy & Security →
Automation*; until then, clicking still brings the app forward but can't select the exact tab.
Focusing **Cursor** needs no extra permission.

Install the hooks once (idempotent and non-destructive — it backs up and preserves any existing
hooks):

```bash
Integrations/agent-hooks/install.sh
```

This copies the writer + gate scripts into `~/.claude/hooks/` and `~/.cursor/hooks/`, adds the
missing Claude Code hook entries (`UserPromptSubmit`/`Notification`/`SubagentStop` plus the
`PreToolUse` gate), creates/merges `~/.cursor/hooks.json`, and creates the `agent-commands`
back-channel directories. Claude Code applies the hooks to newly started sessions; Cursor reloads
`hooks.json` on save.

Remove them just as cleanly (strips only Perch's entries, preserving your other hooks, with
backups):

```bash
Integrations/agent-hooks/uninstall.sh            # leaves state dirs in place
Integrations/agent-hooks/uninstall.sh --purge-state   # also removes state/command dirs
```

A session is shown as working only while its status file was updated recently (a short TTL), so a
turn that ends without a terminal event still clears on its own.

### Agent Control (approve / deny / stop)

Enable *AI Agents → Control (approve/deny/stop)* (off by default) to let Perch act on agents, not
just watch them. With Control on, the gate hooks route side-effecting tool calls
(`Bash`/`Write`/`Edit`/`MultiEdit`/`NotebookEdit`/`WebFetch` for Claude; shell/MCP for Cursor)
through the island: the call pauses, the row surfaces inline **Approve** / **Deny** buttons (with
an optional steering note), and **Stop** best-effort interrupts the run.

The decision travels back to the agent via a per-session command file Perch writes into
`~/.claude/agent-commands` / `~/.cursor/agent-commands`, which the gate hook polls. Safety is built
in: Control is **off by default**, and the Claude gate **never auto-allows** — on timeout it defers
to Claude's native permission prompt rather than silently approving. Decisions are matched by a
`request_id` so a stale decision can't apply to a later call.

## Tests

```bash
swift test
```

Unit tests cover the security-sensitive pure logic: the AppleScript input validators, the command
filename sanitizer, the `pmset` parser, now-playing parsing, agent state/`pid`/`token` coercion,
and the island layout math. `XCTest` ships with Xcode, so if your active toolchain is the Command
Line Tools, point `swift test` at Xcode:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Why not MediaRemote?

Reading system-wide now-playing info historically used the private `MediaRemote` framework. As of
macOS 15.4, `mediaremoted` checks caller entitlements and returns nothing for unentitled
third-party apps, so Perch uses AppleScript for Music/Spotify instead. A future upgrade can add
arbitrary-app support via the `mediaremote-adapter` (a helper loaded by an entitled platform binary).

## Architecture

```
Sources/Perch/
  main.swift                       NSApplication bootstrap (.accessory policy)
  AppDelegate.swift                wires services, window, menu-bar item, full-screen observer
  AppServices.swift                hub: state + services + user actions
  State/IslandState.swift          single source of truth (ObservableObject) + persisted toggles
  Window/
    NotchGeometry.swift            resolves the built-in notched display + notch dimensions
    IslandLayout.swift             pure geometry: window/collapsed/expanded/hover rects
    NotchWindow.swift              borderless, transparent, shielding-level window
    IslandContainerView.swift      click-through hit-testing + tracking-area hover
    NotchWindowController.swift    hover→expand/collapse, screen-reconfig handling
    FullScreenObserver.swift       hides island when another app is full-screen
  UI/
    IslandRootView.swift           morphs between collapsed / peek / agent-live / expanded
    CompactView.swift              activity peek (flanks the notch)
    AgentViews.swift               agent live ear + expanded "AI Agents" section + controls
    ExpandedView.swift             now-playing + battery + AI agents
    IslandTheme.swift              shared colors / metrics / appearance helpers
  Services/
    MediaService.swift             AppleScript + distributed-notification observers
    BatteryService.swift           IOKit power sources (event-driven)
    VolumeService.swift            CoreAudio volume/mute listeners + transient HUD
    PowerModeService.swift         Energy Mode read + privileged helper install/uninstall
    AgentStatusService.swift       FSEvents watcher for Claude Code / Cursor agent status
    AgentFocusService.swift        click-to-focus: raises the agent's terminal tab / editor window
    AgentNotificationService.swift Notification Center alert + sound when an agent starts waiting
    AgentCommandService.swift      writes approve/deny/stop decisions + gating config (Control)
    ActivityCenter.swift           drives transient live-activity peeks
Tests/PerchTests/                  unit tests for the pure validation / parsing / layout logic
Resources/Info.plist               LSUIElement + stable CFBundleIdentifier + usage strings
Integrations/agent-hooks/          Claude Code + Cursor hook scripts + install.sh / uninstall.sh
scripts/uninstall-powermode.sh     standalone removal of the Energy Mode root helper
bundle.sh                          build + assemble + ad-hoc codesign
```

## License

[MIT](LICENSE) © 2026 Shamsiddin Nabiev
