#!/bin/zsh
set -euo pipefail

VERSION="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/Build/Whitesnake.app"
DMG_NAME="Whitesnake-${VERSION}.dmg"
TMP_DIR=$(mktemp -d)

# Copy app using ditto (handles app bundles correctly)
ditto "$APP_PATH" "$TMP_DIR/Whitesnake.app"

# Strip provenance attribute only (DO NOT remove code signature - it corrupts the binary)
find "$TMP_DIR/Whitesnake.app" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

ln -s /Applications "$TMP_DIR/Applications"

hdiutil create \
    -volname "Whitesnake ${VERSION}" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$ROOT/$DMG_NAME"

rm -rf "$TMP_DIR"
printf 'Created %s\n' "$ROOT/$DMG_NAME"
