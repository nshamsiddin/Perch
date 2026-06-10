#!/bin/bash
# Build Perch.app and package it into a distributable Perch.dmg (drag-to-Applications).
#
# Uses `create-dmg` (brew install create-dmg) for a styled Finder window when it's available, and
# otherwise falls back to a plain `hdiutil` image — so this works the same locally and in headless
# CI (where create-dmg's Finder styling isn't reliable).
#
# Signing note: bundle.sh ad-hoc signs the app, which is fine for personal use but trips Gatekeeper
# on other Macs (right-click -> Open the first time, or `xattr -dr com.apple.quarantine Perch.app`).
# For a warning-free install on machines you don't control, sign the app with a Developer ID
# certificate and notarize it before running this script.
set -euo pipefail

APP_NAME="Perch"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_DIR="$ROOT/$APP_NAME.app"
DMG_PATH="$ROOT/$APP_NAME.dmg"

echo "==> Building app bundle…"
./bundle.sh

echo "==> Packaging $APP_NAME.dmg…"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
    # create-dmg can exit non-zero on cosmetic AppleScript/Finder steps even when the image was
    # written, so don't abort the script on its failure — we verify the output below.
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 540 380 \
        --icon-size 110 \
        --icon "$APP_NAME.app" 150 180 \
        --app-drop-link 390 180 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$APP_DIR" || true
fi

# Fall back to a plain image if create-dmg is absent or didn't produce the file.
if [ ! -f "$DMG_PATH" ]; then
    echo "    (using hdiutil)"
    STAGING="$(mktemp -d)"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
    rm -rf "$STAGING"
fi

echo "==> Done: $DMG_PATH"
