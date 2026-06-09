# Islet

A Dynamic Island for the macOS notch. Islet is a lightweight, native AppKit background app
that draws an interactive island around the notch (or a centered pill on non-notch Macs).
Hover to expand it into a panel with now-playing controls and battery/system status.
Transient "live activity" peeks slide out around the notch when things happen.

Built with Swift Package Manager — no Xcode project required.

## Features

- **Hover to expand** — a borderless, transparent window pinned over the notch expands into a
  panel on hover. Uses an `NSTrackingArea(.activeAlways)`, so **no Accessibility permission** is
  needed and there's no polling.
- **Now Playing** — title/artist + play-pause / next / previous for **Music** and **Spotify**,
  driven by each app's distributed notifications for instant updates (with a slow timer fallback).
- **AI agent status** — a live indicator flanks the notch while **Claude Code** and/or **Cursor**
  agents are actively working (tool glyphs + a "thinking" pulse + session count). The pulse turns
  amber when an agent is waiting for input. Hover to see a clean, label-free agent overview: a slim
  working / waiting summary above per-session rows (keyed by project, with a live "what it's doing"
  line and elapsed time), sessions awaiting input floated to the top. Detection is hook-driven —
  see *AI agent tracking* below. The overview doubles as a control surface:
  - **Click a row to jump to that agent** — Islet brings the owning window to the front: Cursor's
    workspace window, or the exact terminal tab (Apple Terminal by tty, iTerm2 by session id),
    falling back to simply activating the app.
  - **Waiting alerts** — when an agent newly needs input, the island flashes amber and (optionally)
    a Notification Center banner + sound fires. Tap the notification to jump straight to the agent.
    Toggle this under *AI Agents → Notify on waiting* in the menu-bar menu.
  - **Stuck detection** — a working session that goes quiet too long shows its elapsed time in
    amber, so a wedged or long-running agent stands out at a glance.
- **Live activity peeks** — brief notch-flanking peeks for track changes and power events.
- **Automatic light / dark** — the expanded panel follows the system appearance and switches
  live. The collapsed pill and peeks stay dark on purpose so they blend with the physical notch.
- **Battery / power** — charge % and charging state via IOKit (event-driven).
- **Full-screen aware** — hides while another app is full-screen (the system overlays the notch).

## Requirements

- macOS 13+ (Apple Silicon or notch Mac recommended; works with a pill on non-notch Macs)
- Swift toolchain (Command Line Tools are enough — full Xcode not required)

## Build & run

```bash
chmod +x bundle.sh
./bundle.sh
open Islet.app
```

`bundle.sh` builds a release binary, assembles `Islet.app` (with `LSUIElement` so there's no
Dock icon), and **ad-hoc code-signs** it with a stable bundle identifier. Quit anytime from the
menu-bar icon.

## Permissions

- **Automation (Apple Events)** — the first time Islet reads or controls Music/Spotify, macOS
  prompts to allow automating that app. Approve it in
  *System Settings → Privacy & Security → Automation*. Until then, media info/controls stay idle.
- **No Accessibility permission** is required (hover uses a tracking area, not a global monitor).

### A note on rebuilds and permissions

macOS ties Automation grants to the app's bundle id + code signature. `bundle.sh` re-signs with a
**stable** identity on every build so grants survive rebuilds. If a grant ever gets dropped after a
rebuild, just re-approve it in Automation settings.

## AI agent tracking (Claude Code + Cursor)

The agent indicator is driven by lightweight **hooks** that each tool runs on its agent lifecycle
events. The hooks write a small per-session JSON status file; Islet watches those directories with
FSEvents (event-driven, no polling at rest) and shows the *active* sessions.

- **Claude Code** → `~/.claude/agent-tui-state/<session>.json`. The `Stop` event marks a session
  done, `Notification` marks it waiting for input, and tool/prompt events mark it working. The
  writer also records a short, privacy-safe activity phrase (a tool name plus a file basename or a
  command's program token — never full prompts or arguments) and best-effort focus hints (the
  hosting app's bundle id, terminal session id, and tty) used for click-to-focus.
- **Cursor** → `~/.cursor/agent-status/<conversation>.json`, written on `beforeSubmitPrompt`
  (working), `afterFileEdit` / `beforeShellExecution` (working + activity), and `stop` (done).

The first time you click a row that targets **Apple Terminal** or **iTerm2**, macOS prompts to
allow Islet to control that app (Automation). Approve it in *System Settings → Privacy & Security →
Automation*; until then, clicking still brings the app forward but can't select the exact tab.
Focusing **Cursor** needs no extra permission. A waiting alert also asks for Notification permission
the first time it would fire.

Install the hooks once (idempotent and non-destructive — it backs up and preserves any existing
hooks):

```bash
Integrations/agent-hooks/install.sh
```

This copies the writer scripts into `~/.claude/hooks/` and `~/.cursor/hooks/`, adds the missing
Claude Code hook entries (`UserPromptSubmit`/`Notification`/`SubagentStop`), and creates/merges
`~/.cursor/hooks.json`. Claude Code applies the hooks to newly started sessions; Cursor reloads
`hooks.json` on save. No extra macOS permissions are required (FSEvents on your own directories).

A session is shown as working only while its status file was updated recently (a short TTL), so a
turn that ends without a terminal event still clears on its own.

## Why not MediaRemote?

Reading system-wide now-playing info historically used the private `MediaRemote` framework. As of
macOS 15.4, `mediaremoted` checks caller entitlements and returns nothing for unentitled
third-party apps, so Islet uses AppleScript for Music/Spotify instead. A future upgrade can add
artwork and arbitrary-app support via the `mediaremote-adapter` (a helper loaded by an entitled
platform binary).

## Architecture

```
Sources/Islet/
  main.swift                       NSApplication bootstrap (.accessory policy)
  AppDelegate.swift                wires services, window, menu-bar item, full-screen observer
  AppServices.swift                hub: state + services + user actions
  State/IslandState.swift          single source of truth (ObservableObject)
  Window/
    NotchGeometry.swift            resolves the built-in notched display + notch dimensions
    IslandLayout.swift             pure geometry: window/collapsed/expanded/hover rects
    NotchWindow.swift              borderless, transparent, shielding-level window
    IslandContainerView.swift      click-through hit-testing + tracking-area hover
    NotchWindowController.swift     hover→expand/collapse, screen-reconfig handling
    FullScreenObserver.swift       hides island when another app is full-screen
  UI/
    IslandRootView.swift           morphs between collapsed / peek / agent-live / expanded
    CompactView.swift              activity peek (flanks the notch)
    AgentViews.swift               agent live ear + expanded "AI Agents" section
    ExpandedView.swift             now-playing + battery + AI agents
  Services/
    MediaService.swift             AppleScript + distributed-notification observers
    BatteryService.swift           IOKit power sources (event-driven)
    AgentStatusService.swift       FSEvents watcher for Claude Code / Cursor agent status
    AgentFocusService.swift        click-to-focus: raises the agent's terminal tab / editor window
    AgentNotificationService.swift Notification Center alert + sound when an agent starts waiting
    ActivityCenter.swift           drives transient live-activity peeks
Resources/Info.plist               LSUIElement + stable CFBundleIdentifier + usage strings
Integrations/agent-hooks/          Claude Code + Cursor hook scripts + idempotent install.sh
bundle.sh                          build + assemble + ad-hoc codesign
```
