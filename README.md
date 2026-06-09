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
    IslandRootView.swift           morphs between collapsed / peek / expanded
    CompactView.swift              activity peek (flanks the notch)
    ExpandedView.swift             now-playing + battery
  Services/
    MediaService.swift             AppleScript + distributed-notification observers
    BatteryService.swift           IOKit power sources (event-driven)
    ActivityCenter.swift           drives transient live-activity peeks
Resources/Info.plist               LSUIElement + stable CFBundleIdentifier + usage strings
bundle.sh                          build + assemble + ad-hoc codesign
```
