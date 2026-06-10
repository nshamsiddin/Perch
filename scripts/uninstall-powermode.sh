#!/bin/bash
#
# Perch - remove the Energy Mode helper.
#
# The Energy Mode feature installs a small root LaunchDaemon that applies `pmset powermode`
# changes on Perch's behalf (so each switch is silent after a single admin prompt). This script
# tears all of that down: it boots out and removes the LaunchDaemon, and deletes the support
# directory (apply script + trigger file). Safe to run repeatedly; a no-op if nothing is installed.
#
# Run as root:
#   sudo scripts/uninstall-powermode.sh
#
# The same teardown is available in-app under the menu-bar icon: Energy Mode -> Remove Perch helper.
set -euo pipefail

PLIST="/Library/LaunchDaemons/com.perch.powermode.plist"
SUPPORT_DIR="/Library/Application Support/Perch"

if [ "$(id -u)" -ne 0 ]; then
    echo "This uninstaller must run as root. Re-run with:" >&2
    echo "  sudo $0" >&2
    exit 1
fi

# Bootout (modern) with a fallback to legacy unload; ignore errors if it was never loaded.
/bin/launchctl bootout system "$PLIST" 2>/dev/null \
    || /bin/launchctl unload -w "$PLIST" 2>/dev/null \
    || true

/bin/rm -f "$PLIST"
/bin/rm -rf "$SUPPORT_DIR"

echo "Removed the Perch Energy Mode helper (LaunchDaemon + support files)."
