#!/bin/bash
# Build Perch and assemble a runnable .app bundle, then ad-hoc code-sign it.
#
# Ad-hoc signing with a STABLE bundle identifier matters: macOS keys TCC grants
# (e.g. Automation access for Music/Spotify) off bundle id + code signature. Signing
# every build keeps those grants from being silently dropped across rebuilds.
set -euo pipefail

APP_NAME="Perch"
BUNDLE_ID="com.perch.Perch"
CONFIG="release"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$ROOT/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Ad-hoc code-signing (stable identity for TCC)…"
codesign --force --deep --sign - \
    --identifier "$BUNDLE_ID" \
    "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Run with:  open \"$APP_DIR\""
