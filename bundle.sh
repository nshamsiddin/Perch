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
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
RES_DIR="$APP_DIR/Contents/Resources"

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RES_DIR"

cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# SwiftPM links Sparkle via @rpath but does not embed it in a hand-assembled .app bundle.
SPARKLE_SRC="$BIN_PATH/Sparkle.framework"
if [ ! -d "$SPARKLE_SRC" ]; then
    SPARKLE_SRC="$(find "$ROOT/.build/artifacts/sparkle" -path '*/Sparkle.framework' -type d 2>/dev/null | head -1)"
fi
if [ -z "$SPARKLE_SRC" ] || [ ! -d "$SPARKLE_SRC" ]; then
    echo "Sparkle.framework not found; run swift build first" >&2
    exit 1
fi
echo "==> Embedding Sparkle.framework…"
cp -R "$SPARKLE_SRC" "$FRAMEWORKS_DIR/"
if ! otool -l "$MACOS_DIR/$APP_NAME" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"
fi

# Stamp a release version into the BUNDLED plist only. Releases derive PERCH_VERSION
# from the git tag, so the installed app reports the tagged version while the tracked
# Resources/Info.plist keeps its default for ordinary local builds.
if [ -n "${PERCH_VERSION:-}" ]; then
    echo "==> Stamping version $PERCH_VERSION into bundled Info.plist…"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PERCH_VERSION" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PERCH_VERSION" "$APP_DIR/Contents/Info.plist"
fi

# Release builds stamp the Sparkle EdDSA public key (generate_keys → SUPublicEDKey).
if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
    echo "==> Stamping Sparkle EdDSA public key into bundled Info.plist…"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP_DIR/Contents/Info.plist"
fi

# Universal now playing via mediaremote-adapter (optional; build with scripts/setup-mediaremote-adapter.sh).
ADAPTER_SRC="$ROOT/Resources/MediaRemoteAdapter"
if [ -d "$ADAPTER_SRC" ]; then
    echo "==> Bundling MediaRemote adapter…"
    mkdir -p "$RES_DIR/MediaRemoteAdapter"
    cp -R "$ADAPTER_SRC/"* "$RES_DIR/MediaRemoteAdapter/" 2>/dev/null || true
fi

echo "==> Ad-hoc code-signing (stable identity for TCC)…"
codesign --force --deep --sign - \
    --identifier "$BUNDLE_ID" \
    "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Run with:  open \"$APP_DIR\""
