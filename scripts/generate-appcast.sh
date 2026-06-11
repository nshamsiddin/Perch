#!/bin/bash
# Generate a Sparkle 2 appcast for a release DMG and sign the enclosure with EdDSA.
#
# Requires SPARKLE_PRIVATE_KEY (EdDSA private key from `generate_keys`) in the
# environment for a signed appcast. Without it, the appcast is written with an
# empty signature (useful only for dry runs).
#
# Usage: generate-appcast.sh <dmg-path> <git-tag> <version>
#   e.g. generate-appcast.sh Perch-v1.0.3.dmg v1.0.3 1.0.3
set -euo pipefail

DMG_PATH="${1:?DMG path required}"
TAG="${2:?git tag required (e.g. v1.0.3)}"
VERSION="${3:?version required (e.g. 1.0.3)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f "$DMG_PATH" ]; then
    echo "DMG not found: $DMG_PATH" >&2
    exit 1
fi

# Resolve Sparkle so sign_update matches the Package.swift dependency version.
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift package resolve >/dev/null

SIGN_UPDATE="$(find "$ROOT/.build/artifacts/sparkle" -path '*/bin/sign_update' -type f 2>/dev/null | head -1)"
if [ -z "$SIGN_UPDATE" ] || [ ! -x "$SIGN_UPDATE" ]; then
    echo "sign_update not found; run swift package resolve first" >&2
    exit 1
fi

DMG_NAME="$(basename "$DMG_PATH")"
DOWNLOAD_URL="https://github.com/nshamsiddin/Perch/releases/download/${TAG}/${DMG_NAME}"
LENGTH="$(stat -f%z "$DMG_PATH")"

ED_SIGNATURE=""
KEY_FILE=""
BASELINE=""
cleanup() {
    rm -f ${KEY_FILE:+"$KEY_FILE"} ${BASELINE:+"$BASELINE"}
}
trap cleanup EXIT

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    KEY_FILE="$(mktemp)"
    printf '%s\n' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    SIGN_OUTPUT="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG_PATH")"
    ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    if [ -z "$ED_SIGNATURE" ]; then
        echo "Failed to parse EdDSA signature from sign_update output" >&2
        exit 1
    fi
else
    echo "WARNING: SPARKLE_PRIVATE_KEY not set; appcast will have an empty signature" >&2
fi

PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

NEW_ITEM=$(cat <<ITEM
        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure url="${DOWNLOAD_URL}"
                       sparkle:edSignature="${ED_SIGNATURE}"
                       length="${LENGTH}"
                       type="application/octet-stream" />
        </item>
ITEM
)

# Prefer the live feed on master so release builds prepend instead of replacing history.
BASELINE="$(mktemp)"
if git show origin/master:appcast.xml > "$BASELINE" 2>/dev/null; then
    :
elif [ -f "$ROOT/appcast.xml" ]; then
    cp "$ROOT/appcast.xml" "$BASELINE"
fi

if [ -s "$BASELINE" ] && grep -q '<item>' "$BASELINE"; then
    if grep -q "<sparkle:version>${VERSION}</sparkle:version>" "$BASELINE"; then
        echo "Version ${VERSION} already present in appcast.xml; leaving feed unchanged" >&2
        cp "$BASELINE" "$ROOT/appcast.xml"
        exit 0
    fi
    EXISTING_ITEMS="$(awk '/^[[:space:]]*<item>/,/^[[:space:]]*<\/item>/' "$BASELINE")"
    cat > "$ROOT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Perch</title>
        <link>https://github.com/nshamsiddin/Perch</link>
        <description>Most recent updates to Perch</description>
        <language>en</language>
${NEW_ITEM}
${EXISTING_ITEMS}
    </channel>
</rss>
EOF
else
    cat > "$ROOT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Perch</title>
        <link>https://github.com/nshamsiddin/Perch</link>
        <description>Most recent updates to Perch</description>
        <language>en</language>
${NEW_ITEM}
    </channel>
</rss>
EOF
fi

echo "==> Wrote appcast.xml (enclosure: ${DOWNLOAD_URL})"
