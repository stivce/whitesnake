#!/bin/zsh
set -euo pipefail

VERSION="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/Build/Whitesnake.app"
DMG_NAME="Whitesnake-${VERSION}.dmg"
TMP_DIR=$(mktemp -d)

# Copy app using ditto (preserves structure better than cp)
ditto "$APP_PATH" "$TMP_DIR/Whitesnake.app"

# Remove any broken signatures (Swift PM builds produce invalid signatures)
codesign --remove-signature "$TMP_DIR/Whitesnake.app" 2>/dev/null || true

# Strip all extended attributes (quarantine, provenance, etc.)
xattr -cr "$TMP_DIR/Whitesnake.app" 2>/dev/null || true

ln -s /Applications "$TMP_DIR/Applications"

hdiutil create \
    -volname "Whitesnake ${VERSION}" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$ROOT/$DMG_NAME"

rm -rf "$TMP_DIR"
printf 'Created %s\n' "$ROOT/$DMG_NAME"
