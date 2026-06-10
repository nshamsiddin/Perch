#!/bin/bash
# Fetch and build mediaremote-adapter for universal now playing support.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/MediaRemoteAdapter"
WORK="$ROOT/.build/mediaremote-adapter-src"

echo "==> Cloning mediaremote-adapter…"
rm -rf "$WORK"
git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git "$WORK"

echo "==> Building MediaRemoteAdapter.framework…"
mkdir -p "$WORK/build"
cd "$WORK/build"
cmake ..
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"

echo "==> Installing into Resources/MediaRemoteAdapter…"
mkdir -p "$DEST"
cp "$WORK/bin/mediaremote-adapter.pl" "$DEST/"
cp -R "$WORK/build/MediaRemoteAdapter.framework" "$DEST/"
echo "Done. Re-run ./bundle.sh to include the adapter in Perch.app."
