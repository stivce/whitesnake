#!/bin/zsh
set -euo pipefail

VERSION="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/Build/Whitesnake.app"
DMG_NAME="Whitesnake-${VERSION}.dmg"
TMP_DIR=$(mktemp -d)

cp -r "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

hdiutil create \
    -volname "Whitesnake ${VERSION}" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$ROOT/$DMG_NAME"

rm -rf "$TMP_DIR"
printf 'Created %s\n' "$ROOT/$DMG_NAME"
