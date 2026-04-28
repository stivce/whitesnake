#!/bin/zsh
set -euo pipefail

VERSION="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/Build/Whitesnake.app"
DMG_NAME="Whitesnake-${VERSION}.dmg"
TMP_DIR=$(mktemp -d)

# Copy app preserving all attributes
cp -a "$APP_PATH" "$TMP_DIR/Whitesnake.app"

# Strip provenance attributes
find "$TMP_DIR/Whitesnake.app" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

# Ad-hoc sign ONLY the main executable (deep signing breaks embedded frameworks)
codesign --force --sign - "$TMP_DIR/Whitesnake.app/Contents/MacOS/Whitesnake" 2>/dev/null || true

ln -s /Applications "$TMP_DIR/Applications"

hdiutil create \
    -volname "Whitesnake ${VERSION}" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$ROOT/$DMG_NAME"

rm -rf "$TMP_DIR"
printf 'Created %s\n' "$ROOT/$DMG_NAME"
